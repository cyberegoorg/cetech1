#/bin/sh

~/.dotnet/tools/castffi extract --config ./config-macos.json
~/.dotnet/tools/castffi merge --inputDirectoryPath  ./ast/  --outputFilePath ./cross-platform-ast.json
~/.dotnet/tools/c2cs generate --config ./config-generate-cs.json