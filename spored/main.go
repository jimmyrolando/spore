// spored: Spore's services, the parts a Quickshell shell can't do on its
// own, in one small program. The shell starts it with the session
// (shell/services/Spored.qml) and starts it again if it ends.
//
// For now it offers one: org.freedesktop.FileManager1 (filemanager.go), so a
// browser's "Show in folder" opens Spore Files.
package main

import (
	"flag"
	"log"
	"os"
	"os/signal"
	"syscall"

	"github.com/godbus/dbus/v5"
)

func main() {
	log.SetFlags(0)
	log.SetPrefix("spored: ")
	files := flag.String("files", "", "the spore-files command (default: from PATH)")
	flag.Parse()

	conn, err := dbus.ConnectSessionBus()
	if err != nil {
		log.Fatalf("no session bus: %v", err)
	}
	defer conn.Close()

	if err := serveFileManager(conn, filesCommand(*files)); err != nil {
		log.Fatal(err)
	}

	// Until the shell stops it, or the bus goes away.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	select {
	case <-stop:
	case <-conn.Context().Done():
		log.Fatal("the session bus closed")
	}
}
