# spored: Spore's services, in Go (spored/). spore-shell puts it in its bin.
{
  lib,
  buildGoModule,
}:

buildGoModule {
  pname = "spored";
  version = "0.2.2";

  src = lib.fileset.toSource {
    root = ../spored;
    fileset = lib.fileset.unions [
      ../spored/go.mod
      ../spored/go.sum
      (lib.fileset.fileFilter (file: file.hasExt "go") ../spored)
    ];
  };

  vendorHash = "sha256-VtGat4ek0ij8GOx68MQPNFtBuansj/d1GCOgfLOiGwM=";

  env.CGO_ENABLED = "0";
  ldflags = [
    "-s"
    "-w"
  ];

  meta = {
    description = "Spore's services: org.freedesktop.FileManager1 for Spore Files";
    homepage = "https://github.com/jimmyrolando/spore";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "spored";
  };
}
