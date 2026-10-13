#!/bin/sh
# Package and install the extension. There is no node/vsce on this machine,
# so the .vsix (a zip: manifest + extension/) is put together by hand.
set -e
cd "$(dirname "$0")"
version=$(/usr/bin/python3 -c 'import json; print(json.load(open("package.json"))["version"])')
stage=$(mktemp -d)
trap 'rm -rf "$stage"' EXIT
mkdir "$stage/extension"
cp -r package.json extension.js zathurarc.js media "$stage/extension/"
types=$(find "$stage/extension" -type f -name '*.*' | sed 's/.*\.//' | sort -u |
    while read -r ext; do printf '<Default Extension=".%s" ContentType="application/octet-stream"/>' "$ext"; done)
cat > "$stage/[Content_Types].xml" <<XML
<?xml version="1.0" encoding="utf-8"?>
<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension=".vsixmanifest" ContentType="text/xml"/>$types</Types>
XML
cat > "$stage/extension.vsixmanifest" <<XML
<?xml version="1.0" encoding="utf-8"?>
<PackageManifest Version="2.0.0" xmlns="http://schemas.microsoft.com/developer/vsx-schema/2011" xmlns:d="http://schemas.microsoft.com/developer/vsx-schema-design/2011">
  <Metadata>
    <Identity Language="en-US" Id="pdf-zathura" Version="$version" Publisher="local"/>
    <DisplayName>PDF in Zathura</DisplayName>
    <Description xml:space="preserve">A zathura-style PDF viewer inside VS Code</Description>
    <Properties>
      <Property Id="Microsoft.VisualStudio.Code.Engine" Value="^1.90.0"/>
      <Property Id="Microsoft.VisualStudio.Code.ExtensionKind" Value="ui"/>
    </Properties>
  </Metadata>
  <Installation><InstallationTarget Id="Microsoft.VisualStudio.Code"/></Installation>
  <Dependencies/>
  <Assets><Asset Type="Microsoft.VisualStudio.Code.Manifest" Path="extension/package.json" Addressable="true"/></Assets>
</PackageManifest>
XML
out="$PWD/pdf-zathura-$version.vsix"
rm -f "$out"
(cd "$stage" && zip -qr "$out" .)
code --install-extension "$out" --force
