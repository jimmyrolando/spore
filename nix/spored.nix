# spored: Spore's services, in Go (spored/). spore-shell puts it in its bin.
{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "spored";
  version = "0.3.0";

  src = lib.fileset.toSource {
    root = ../spored;
    fileset = lib.fileset.unions [
      ../spored/go.mod
      ../spored/go.sum
      (lib.fileset.fileFilter (file: file.hasExt "go") ../spored)
    ];
  };

  vendorHash = "sha256-i7q5q7Tmk9J8fYMHta4EOax5+X6mf4WzPPpsFwBMeLM=";

  env.CGO_ENABLED = "0";
  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Spore's services: FileManager1 for Spore Files, the lock before sleeping, drive events";
    homepage = "https://github.com/jimmyrolando/spore";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "spored";
  };
}
