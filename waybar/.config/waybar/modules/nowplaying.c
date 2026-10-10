/* Now playing — the bottom bar's player as a waybar CFFI module, so that its
 * progress line can be CLICKED and DRAGGED.
 *
 *   cffi/now-playing in ~/.config/waybar/bottom.jsonc
 *   build: ~/.config/waybar/modules/build.sh   (-> nowplaying.so)
 *
 * A waybar `custom` module only learns "it was clicked" — no position, no
 * drag, no hover — so seeking by pointing was impossible. A CFFI module is a
 * real GTK widget inside the bar and gets every pointer event.
 *
 * All the logic stays in ~/.config/hypr/now-playing.py (which player, KDE
 * Connect quirks, colours, text). It runs as a child with --cffi and prints
 * one line per change (fields joined by \x1f, see encode() there). This file
 * only draws and handles the mouse:
 *
 *   * The label is named "custom-now-playing", so bottom.css / progress.css
 *     style it exactly as before (colour per app, pill, the 2px line).
 *   * Pointer over the bottom SEEK_ZONE px: the line thickens, a knob marks
 *     the playhead, and a bubble shows the time under the pointer.
 *   * Click there: jump. Drag: the knob and bubble follow; the seek is sent
 *     on release only (one request to the phone, not dozens).
 *   * Click elsewhere: play/pause. Right-click: players menu. Scroll: ±5 s
 *     (media-seek.sh), honouring "reverse-scrolling" like waybar does.
 *
 *
 * TWO PILLS: bottom.jsonc loads this twice, cffi/now-playing#local and
 * #remote, each with a "scope" that goes to now-playing.py (--scope): this
 * laptop's players / the phone's (KDE Connect + the Spotify Web API bridge).
 * Each is a group [⏮ pill ⏭] with its OWN prev/next ("skip-cmd") and passes
 * its own player to the seek / skip commands, so the two never get mixed up.
 * The whole group hides while its side has nothing to show.
 *
 * Config keys: "script" (now-playing.py), "scope" (local/remote; none = all
 * players in one pill, as before), "seek-cmd", "skip-cmd", "menu-cmd",
 * "reverse-scrolling" ("true"/"false").
 */
#include <math.h>
#include <signal.h>
#include <stdlib.h>
#include <string.h>

#include "waybar_cffi_module.h"

const size_t wbcffi_version = 1;

#define SEEK_ZONE 11      /* px from the pill's bottom edge that seek */
#define LINE_IDLE 2       /* the CSS line, for reference */
#define LINE_HOVER 5
#define KNOB_R 5.0
#define DRAG_SLOP 3       /* px a press must move to count as a drag */

typedef struct {
    GtkWidget *group, *ebox, *overlay, *label, *area;
    GtkWidget *prev_box, *prev, *next_box, *next; /* ⏮ ⏭ beside the pill */
    char *script, *scope, *seek_cmd, *skip_cmd, *menu_cmd;
    gboolean reverse;
    guint tick_id;

    GPid child;
    GIOChannel *chan;
    guint watch, respawn;
    GString *buf;

    /* last state from now-playing.py */
    char **classes;
    char *tooltip, *player;
    gint64 pos_us, len_us, pos_at; /* pos_at: g_get_monotonic_time() of pos_us */
    gboolean playing, hidden;

    /* pointer */
    gboolean in_zone, pressed, press_in_zone, dragging;
    double press_x, ptr_x, drag_frac;
    double scroll_acc;
    gint64 seek_hold_until; /* show the optimistic position until the data catches up */
} Mod;

/* ── helpers ─────────────────────────────────────────────────────────────── */
static gint64 now_pos(Mod *m) {
    gint64 p = m->pos_us;
    if (m->playing && m->pos_at)
        p += g_get_monotonic_time() - m->pos_at;
    if (m->len_us > 0 && p > m->len_us)
        p = m->len_us;
    return p < 0 ? 0 : p;
}

static void fmt_time(gint64 us, char *out, size_t n) {
    gint64 s = us / 1000000;
    if (s >= 3600)
        g_snprintf(out, n, "%" G_GINT64_FORMAT ":%02d:%02d", s / 3600, (int)(s / 60 % 60), (int)(s % 60));
    else
        g_snprintf(out, n, "%" G_GINT64_FORMAT ":%02d", s / 60, (int)(s % 60));
}

/* The pill = the label's allocation minus its CSS margin (where the CSS
 * background, and so the 2px line, is painted). */
static void pill_box(Mod *m, double *x0, double *x1, double *bottom) {
    GtkAllocation a;
    GtkBorder mg;
    GtkStyleContext *ctx = gtk_widget_get_style_context(m->label);
    gtk_widget_get_allocation(m->label, &a);
    gtk_style_context_get_margin(ctx, gtk_style_context_get_state(ctx), &mg);
    *x0 = mg.left;
    *x1 = a.width - mg.right;
    *bottom = a.height - mg.bottom;
}

static double x_to_frac(Mod *m, double x) {
    double x0, x1, b;
    pill_box(m, &x0, &x1, &b);
    if (x1 - x0 < 1)
        return 0;
    double f = (x - x0) / (x1 - x0);
    return f < 0 ? 0 : f > 1 ? 1 : f;
}

static gboolean seekable(Mod *m) { return !m->hidden && m->len_us > 0 && m->player && *m->player; }

static gboolean on_line(Mod *m, double y) { /* geometry only: the bottom strip */
    double x0, x1, b;
    pill_box(m, &x0, &x1, &b);
    return y >= b - SEEK_ZONE;
}

/* The line is live whenever a player is shown — playing OR paused (seeking
 * while paused is wanted). With no player at all the module hides and the
 * bar shows custom/media-idle's "---" with a faint, inert line instead. */
static gboolean in_zone(Mod *m, double y) { return seekable(m) && on_line(m, y); }

static void spawn(const char *const *argv) {
    GError *err = NULL;
    if (!g_spawn_async(NULL, (char **)argv, NULL, G_SPAWN_SEARCH_PATH | G_SPAWN_STDOUT_TO_DEV_NULL |
                       G_SPAWN_STDERR_TO_DEV_NULL, NULL, NULL, NULL, &err)) {
        g_warning("nowplaying: %s", err->message);
        g_error_free(err);
    }
}

static void set_cursor(Mod *m, gboolean pointer) {
    GdkWindow *w = gtk_widget_get_window(m->ebox);
    if (!w)
        return;
    GdkCursor *c = pointer ? gdk_cursor_new_from_name(gdk_window_get_display(w), "pointer") : NULL;
    gdk_window_set_cursor(w, c);
    if (c)
        g_object_unref(c);
}

/* ── drawing: only while hovering the line / dragging ────────────────────── */
static gboolean on_draw(GtkWidget *w, cairo_t *cr, Mod *m) {
    (void)w;
    if (!(m->in_zone || m->dragging) || !seekable(m))
        return FALSE;
    double x0, x1, b;
    pill_box(m, &x0, &x1, &b);
    GdkRGBA fg;
    GtkStyleContext *ctx = gtk_widget_get_style_context(m->label);
    gtk_style_context_get_color(ctx, gtk_style_context_get_state(ctx), &fg);

    double played = m->dragging ? m->drag_frac : (double)now_pos(m) / (double)m->len_us;
    double y = b - LINE_HOVER / 2.0 - 1;

    /* track + elapsed, round caps, a little inset so the caps clear the radius */
    double inset = 6, tx0 = x0 + inset, tx1 = x1 - inset;
    cairo_set_line_cap(cr, CAIRO_LINE_CAP_ROUND);
    cairo_set_line_width(cr, LINE_HOVER);
    cairo_set_source_rgba(cr, 0.27, 0.28, 0.35, 0.95); /* @surface1 */
    cairo_move_to(cr, tx0, y);
    cairo_line_to(cr, tx1, y);
    cairo_stroke(cr);
    double px = tx0 + (tx1 - tx0) * played;
    gdk_cairo_set_source_rgba(cr, &fg);
    cairo_move_to(cr, tx0, y);
    cairo_line_to(cr, px, y);
    cairo_stroke(cr);

    /* knob */
    cairo_arc(cr, px, y, KNOB_R, 0, 2 * M_PI);
    cairo_fill(cr);

    /* bubble: time under the pointer (or where the drag will land) */
    double f = m->dragging ? m->drag_frac : x_to_frac(m, m->ptr_x);
    char t[16], l[16], s[40];
    fmt_time((gint64)(f * m->len_us), t, sizeof t);
    fmt_time(m->len_us, l, sizeof l);
    g_snprintf(s, sizeof s, "%s / %s", t, l);
    PangoLayout *lay = gtk_widget_create_pango_layout(m->area, s);
    PangoFontDescription *fd = pango_font_description_from_string("JetBrainsMono Nerd Font Bold 9");
    pango_layout_set_font_description(lay, fd);
    pango_font_description_free(fd);
    int tw, th;
    pango_layout_get_pixel_size(lay, &tw, &th);
    double bw = tw + 12, bh = th + 4;
    double bx = tx0 + (tx1 - tx0) * f - bw / 2;
    if (bx < x0) bx = x0;
    if (bx + bw > x1) bx = x1 - bw;
    double by = b - LINE_HOVER - 4 - bh;
    if (by < 0) by = 0;
    double r = 5;
    cairo_new_sub_path(cr);
    cairo_arc(cr, bx + bw - r, by + r, r, -M_PI / 2, 0);
    cairo_arc(cr, bx + bw - r, by + bh - r, r, 0, M_PI / 2);
    cairo_arc(cr, bx + r, by + bh - r, r, M_PI / 2, M_PI);
    cairo_arc(cr, bx + r, by + r, r, M_PI, 3 * M_PI / 2);
    cairo_close_path(cr);
    cairo_set_source_rgba(cr, 0.118, 0.118, 0.18, 0.96); /* @base */
    cairo_fill_preserve(cr);
    gdk_cairo_set_source_rgba(cr, &fg);
    cairo_set_line_width(cr, 1);
    cairo_stroke(cr);
    cairo_move_to(cr, bx + 6, by + 2);
    pango_cairo_show_layout(cr, lay);
    g_object_unref(lay);
    return FALSE;
}

static gboolean tick(gpointer data) { /* keep the knob moving while hovered */
    Mod *m = data;
    if ((m->in_zone || m->dragging) && m->playing)
        gtk_widget_queue_draw(m->area);
    return G_SOURCE_CONTINUE;
}

/* ── pointer ─────────────────────────────────────────────────────────────── */
static void update_zone(Mod *m, double y) {
    gboolean z = in_zone(m, y);
    if (z != m->in_zone) {
        m->in_zone = z;
        set_cursor(m, z);
        gtk_widget_set_has_tooltip(m->ebox, !z); /* the bubble replaces it */
    }
    gtk_widget_queue_draw(m->area);
}

static gboolean on_motion(GtkWidget *w, GdkEventMotion *e, Mod *m) {
    (void)w;
    m->ptr_x = e->x;
    if (m->pressed && m->press_in_zone) {
        if (!m->dragging && fabs(e->x - m->press_x) >= DRAG_SLOP)
            m->dragging = TRUE;
        m->drag_frac = x_to_frac(m, e->x);
        gtk_widget_queue_draw(m->area);
        return TRUE;
    }
    update_zone(m, e->y);
    return FALSE;
}

static gboolean on_leave(GtkWidget *w, GdkEventCrossing *e, Mod *m) {
    (void)w;
    if (m->pressed) /* dragging past the edge: keep going */
        return FALSE;
    /* A "leave" at a point still inside us isn't one: GTK/Hyprland send such
     * a crossing (detail NONLINEAR_VIRTUAL) right after the pointer enters —
     * it switched the hover state straight back off (seen in a debug log). */
    if (e->x >= 0 && e->y >= 0 && e->x < gtk_widget_get_allocated_width(m->ebox) &&
        e->y < gtk_widget_get_allocated_height(m->ebox))
        return FALSE;
    m->in_zone = FALSE;
    set_cursor(m, FALSE);
    gtk_widget_set_has_tooltip(m->ebox, TRUE);
    gtk_widget_queue_draw(m->area);
    return FALSE;
}

static gboolean on_press(GtkWidget *w, GdkEventButton *e, Mod *m) {
    (void)w;
    if (e->type != GDK_BUTTON_PRESS)
        return TRUE; /* swallow double/triple-click extras */
    if (e->button == 1) {
        m->pressed = TRUE;
        m->press_x = e->x;
        m->press_in_zone = in_zone(m, e->y);
        m->dragging = FALSE;
        if (m->press_in_zone) {
            m->drag_frac = x_to_frac(m, e->x);
            gtk_widget_queue_draw(m->area);
        }
        return TRUE;
    }
    if (e->button == 3 && m->menu_cmd) {
        const char *argv[] = {"/bin/sh", "-c", m->menu_cmd, NULL};
        spawn(argv);
        return TRUE;
    }
    return FALSE;
}

static gboolean on_release(GtkWidget *w, GdkEventButton *e, Mod *m) {
    (void)w;
    if (e->button != 1 || !m->pressed)
        return FALSE;
    m->pressed = FALSE;
    if (m->press_in_zone && seekable(m)) {
        /* click or end of drag on the line: one absolute seek */
        double f = m->dragging ? m->drag_frac : x_to_frac(m, e->x);
        gint64 target = (gint64)(f * m->len_us);
        char us[32];
        g_snprintf(us, sizeof us, "%" G_GINT64_FORMAT, target);
        const char *argv[] = {"/usr/bin/python3", m->script, "seekto", m->player, us, NULL};
        spawn(argv);
        m->pos_us = target; /* optimistic, until now-playing.py reports */
        m->pos_at = g_get_monotonic_time();
        m->seek_hold_until = m->pos_at + 2 * G_USEC_PER_SEC;
        m->dragging = FALSE;
        update_zone(m, e->y);
    } else if (!m->hidden && m->player && *m->player) {
        const char *argv[] = {"playerctl", "-p", m->player, "play-pause", NULL};
        spawn(argv);
    }
    return TRUE;
}

static gboolean on_scroll(GtkWidget *w, GdkEventScroll *e, Mod *m) {
    (void)w;
    int dir = 0; /* +1 = up */
    if (e->direction == GDK_SCROLL_UP)
        dir = 1;
    else if (e->direction == GDK_SCROLL_DOWN)
        dir = -1;
    else if (e->direction == GDK_SCROLL_SMOOTH) {
        m->scroll_acc += e->delta_y;
        if (m->scroll_acc <= -1.0) { dir = 1; m->scroll_acc = 0; }
        else if (m->scroll_acc >= 1.0) { dir = -1; m->scroll_acc = 0; }
    }
    if (!dir || !m->seek_cmd || m->hidden)
        return TRUE;
    /* "reverse-scrolling" undoes the TOUCHPAD's natural scrolling only (as
     * waybar's own option does). Flipping the mouse wheel too made wheel-up
     * go backward. Now wheel up = forward, two-finger swipe up = forward. */
    GdkDevice *dev = gdk_event_get_source_device((GdkEvent *)e);
    if (m->reverse && dev && gdk_device_get_source(dev) == GDK_SOURCE_TOUCHPAD)
        dir = -dir;
    const char *argv[] = {m->seek_cmd, dir > 0 ? "5+" : "5-", m->player ? m->player : "", NULL};
    spawn(argv);
    return TRUE;
}

/* ── ⏮ / ⏭ ───────────────────────────────────────────────────────────────── */
/* waybar's own modules get :hover by setting PRELIGHT on enter; do the same
 * so bottom.css's #custom-media-prev:hover applies to ours. */
static gboolean on_btn_cross(GtkWidget *w, GdkEventCrossing *e, gpointer label) {
    (void)w;
    if (e->type == GDK_ENTER_NOTIFY)
        gtk_widget_set_state_flags(label, GTK_STATE_FLAG_PRELIGHT, FALSE);
    else if (e->detail != GDK_NOTIFY_INFERIOR)
        gtk_widget_unset_state_flags(label, GTK_STATE_FLAG_PRELIGHT);
    return FALSE;
}

static gboolean on_btn_press(GtkWidget *w, GdkEventButton *e, Mod *m) {
    if (e->type != GDK_BUTTON_PRESS || e->button != 1 || m->hidden || !m->player || !*m->player)
        return TRUE;
    const char *argv[] = {m->skip_cmd, w == m->prev_box ? "prev" : "next", m->player, NULL};
    spawn(argv);
    return TRUE;
}

static GtkWidget *make_btn(Mod *m, const char *glyph, const char *name, const char *tip,
                           GtkWidget **label) {
    GtkWidget *box = gtk_event_box_new();
    *label = gtk_label_new(glyph);
    gtk_widget_set_name(*label, name); /* bottom.css styles it like before */
    gtk_container_add(GTK_CONTAINER(box), *label);
    gtk_widget_set_tooltip_text(box, tip);
    gtk_widget_add_events(box, GDK_BUTTON_PRESS_MASK | GDK_ENTER_NOTIFY_MASK | GDK_LEAVE_NOTIFY_MASK);
    g_signal_connect(box, "button-press-event", G_CALLBACK(on_btn_press), m);
    g_signal_connect(box, "enter-notify-event", G_CALLBACK(on_btn_cross), *label);
    g_signal_connect(box, "leave-notify-event", G_CALLBACK(on_btn_cross), *label);
    return box;
}

/* ── data from now-playing.py --cffi ─────────────────────────────────────── */
static void apply_line(Mod *m, const char *line) {
    char **f = g_strsplit(line, "\x1f", 7);
    if (g_strv_length(f) < 7) {
        g_strfreev(f);
        return;
    }
    GtkStyleContext *ctx = gtk_widget_get_style_context(m->label);
    if (m->classes)
        for (char **c = m->classes; *c; c++)
            if (**c)
                gtk_style_context_remove_class(ctx, *c);
    g_strfreev(m->classes);
    m->classes = g_strsplit(f[1], " ", -1);
    m->hidden = FALSE;
    for (char **c = m->classes; *c; c++) {
        if (**c)
            gtk_style_context_add_class(ctx, *c);
        if (!strcmp(*c, "hidden"))
            m->hidden = TRUE;
    }

    gtk_label_set_markup(GTK_LABEL(m->label), f[0]);
    g_free(m->tooltip);
    m->tooltip = g_strdelimit(g_strdup(f[2]), "\x1e", '\n');
    gtk_widget_set_tooltip_markup(m->ebox, *m->tooltip ? m->tooltip : NULL);
    if (m->in_zone)
        gtk_widget_set_has_tooltip(m->ebox, FALSE);

    gint64 now = g_get_monotonic_time();
    if (now >= m->seek_hold_until) {
        m->pos_us = g_ascii_strtoll(f[3], NULL, 10);
        m->pos_at = now;
    }
    m->len_us = g_ascii_strtoll(f[4], NULL, 10);
    g_free(m->player);
    m->player = g_strdup(f[5]);
    m->playing = !strcmp(f[6], "1");
    g_strfreev(f);
    if (!seekable(m) && m->in_zone && !m->dragging) { /* line went away under the pointer */
        m->in_zone = FALSE;
        set_cursor(m, FALSE);
        gtk_widget_set_has_tooltip(m->ebox, TRUE);
    }

    if (m->hidden || !*gtk_label_get_text(GTK_LABEL(m->label)))
        gtk_widget_hide(m->group);
    else
        gtk_widget_show_all(m->group);
    gtk_widget_queue_draw(m->area);
}

static void start_child(Mod *m);

static gboolean respawn_cb(gpointer data) {
    Mod *m = data;
    m->respawn = 0;
    start_child(m);
    return G_SOURCE_REMOVE;
}

static gboolean on_child_out(GIOChannel *ch, GIOCondition cond, gpointer data) {
    Mod *m = data;
    if (cond & G_IO_IN) {
        char chunk[4096];
        gsize n = 0;
        GIOStatus st = g_io_channel_read_chars(ch, chunk, sizeof chunk, &n, NULL);
        if (n > 0) {
            g_string_append_len(m->buf, chunk, n);
            char *nl;
            while ((nl = memchr(m->buf->str, '\n', m->buf->len))) {
                *nl = '\0';
                apply_line(m, m->buf->str);
                g_string_erase(m->buf, 0, nl - m->buf->str + 1);
            }
        }
        if (st == G_IO_STATUS_NORMAL || st == G_IO_STATUS_AGAIN)
            return G_SOURCE_CONTINUE;
    }
    /* EOF / error: the script died — restart it like waybar's restart-interval */
    g_io_channel_unref(m->chan);
    m->chan = NULL;
    m->watch = 0;
    if (m->child)
        kill(m->child, SIGTERM); /* closed its stdout but still alive? end it */
    m->respawn = g_timeout_add_seconds(3, respawn_cb, m);
    return G_SOURCE_REMOVE;
}

static void on_child_exit(GPid pid, gint status, gpointer data) {
    (void)status;
    Mod *m = data;
    g_spawn_close_pid(pid); /* reaped by GLib's child watch: no zombie */
    if (m->child == pid)
        m->child = 0;
}

static void start_child(Mod *m) {
    const char *argv[] = {"/usr/bin/python3", m->script, "--cffi",
                          m->scope ? "--scope" : NULL, m->scope, NULL};
    int out = -1;
    GError *err = NULL;
    if (!g_spawn_async_with_pipes(NULL, (char **)argv, NULL, G_SPAWN_DO_NOT_REAP_CHILD, NULL, NULL,
                                  &m->child, NULL, &out, NULL, &err)) {
        g_warning("nowplaying: can't start %s: %s", m->script, err->message);
        g_error_free(err);
        m->respawn = g_timeout_add_seconds(5, respawn_cb, m);
        return;
    }
    g_child_watch_add(m->child, on_child_exit, m);
    m->chan = g_io_channel_unix_new(out);
    g_io_channel_set_close_on_unref(m->chan, TRUE);
    g_io_channel_set_encoding(m->chan, NULL, NULL);
    g_io_channel_set_flags(m->chan, G_IO_FLAG_NONBLOCK, NULL);
    m->watch = g_io_add_watch(m->chan, G_IO_IN | G_IO_HUP | G_IO_ERR, on_child_out, m);
}

/* ── waybar ABI ──────────────────────────────────────────────────────────── */
/* No globals: waybar loads this .so once and calls wbcffi_init per pill. */

void *wbcffi_init(const wbcffi_init_info *init, const wbcffi_config_entry *cfg, size_t n) {
    Mod *m = g_new0(Mod, 1);
    m->buf = g_string_new(NULL);
    m->script = g_build_filename(g_get_home_dir(), ".config/hypr/now-playing.py", NULL);
    m->seek_cmd = g_build_filename(g_get_home_dir(), ".config/hypr/media-seek.sh", NULL);
    m->menu_cmd = g_build_filename(g_get_home_dir(), ".config/hypr/media-menu.sh", NULL);
    m->skip_cmd = g_build_filename(g_get_home_dir(), ".config/hypr/media-skip.sh", NULL);
    for (size_t i = 0; i < n; i++) {
        if (!strcmp(cfg[i].key, "script")) { g_free(m->script); m->script = g_strdup(cfg[i].value); }
        else if (!strcmp(cfg[i].key, "scope")) { g_free(m->scope); m->scope = g_strdup(cfg[i].value); }
        else if (!strcmp(cfg[i].key, "skip-cmd")) { g_free(m->skip_cmd); m->skip_cmd = g_strdup(cfg[i].value); }
        else if (!strcmp(cfg[i].key, "seek-cmd")) { g_free(m->seek_cmd); m->seek_cmd = g_strdup(cfg[i].value); }
        else if (!strcmp(cfg[i].key, "menu-cmd")) { g_free(m->menu_cmd); m->menu_cmd = g_strdup(cfg[i].value); }
        else if (!strcmp(cfg[i].key, "reverse-scrolling")) m->reverse = !strncmp(cfg[i].value, "true", 4);
    }

    GtkContainer *root = init->get_root_widget(init->obj);
    m->ebox = gtk_event_box_new();
    gtk_event_box_set_above_child(GTK_EVENT_BOX(m->ebox), TRUE);
    gtk_widget_add_events(m->ebox, GDK_POINTER_MOTION_MASK | GDK_BUTTON_PRESS_MASK | GDK_BUTTON_RELEASE_MASK |
                                       GDK_SCROLL_MASK | GDK_SMOOTH_SCROLL_MASK | GDK_LEAVE_NOTIFY_MASK |
                                       GDK_ENTER_NOTIFY_MASK);
    m->overlay = gtk_overlay_new();
    m->label = gtk_label_new(NULL);
    gtk_widget_set_name(m->label, "custom-now-playing"); /* bottom.css + progress.css apply */
    m->area = gtk_drawing_area_new();
    gtk_container_add(GTK_CONTAINER(m->overlay), m->label);
    gtk_overlay_add_overlay(GTK_OVERLAY(m->overlay), m->area);
    gtk_overlay_set_overlay_pass_through(GTK_OVERLAY(m->overlay), m->area, TRUE);
    gtk_container_add(GTK_CONTAINER(m->ebox), m->overlay);

    /* [⏮ pill ⏭] — the group is what shows / hides */
    m->group = gtk_box_new(GTK_ORIENTATION_HORIZONTAL, 0);
    gtk_widget_set_name(m->group, "now-playing-group");
    if (m->scope)
        gtk_style_context_add_class(gtk_widget_get_style_context(m->group), m->scope);
    m->prev_box = make_btn(m, "\U000F04AE", "custom-media-prev", "Previous (restarts if it can't go back)", &m->prev);
    m->next_box = make_btn(m, "\U000F04AD", "custom-media-next", "Next", &m->next);
    gtk_box_pack_start(GTK_BOX(m->group), m->prev_box, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(m->group), m->ebox, FALSE, FALSE, 0);
    gtk_box_pack_start(GTK_BOX(m->group), m->next_box, FALSE, FALSE, 0);
    gtk_container_add(root, m->group);

    g_signal_connect(m->area, "draw", G_CALLBACK(on_draw), m);
    g_signal_connect(m->ebox, "motion-notify-event", G_CALLBACK(on_motion), m);
    g_signal_connect(m->ebox, "leave-notify-event", G_CALLBACK(on_leave), m);
    g_signal_connect(m->ebox, "button-press-event", G_CALLBACK(on_press), m);
    g_signal_connect(m->ebox, "button-release-event", G_CALLBACK(on_release), m);
    g_signal_connect(m->ebox, "scroll-event", G_CALLBACK(on_scroll), m);
    m->tick_id = g_timeout_add(250, tick, m);

    gtk_widget_hide(m->group); /* until the first line says what to show */
    start_child(m);
    return m;
}

void wbcffi_deinit(void *instance) {
    Mod *m = instance;
    if (m->tick_id) g_source_remove(m->tick_id);
    if (m->watch) g_source_remove(m->watch);
    if (m->respawn) g_source_remove(m->respawn);
    if (m->chan) g_io_channel_unref(m->chan);
    if (m->child)
        kill(m->child, SIGTERM); /* the child watch is dropped with the loop; init reaps */
    g_string_free(m->buf, TRUE);
    g_strfreev(m->classes);
    g_free(m->tooltip);
    g_free(m->player);
    g_free(m->script);
    g_free(m->scope);
    g_free(m->seek_cmd);
    g_free(m->skip_cmd);
    g_free(m->menu_cmd);
    g_free(m);
}

void wbcffi_update(void *instance) { (void)instance; }
void wbcffi_refresh(void *instance, int signal) { (void)instance; (void)signal; }
void wbcffi_doaction(void *instance, const char *name) { (void)instance; (void)name; }
