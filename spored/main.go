// spored: Spore's services, the parts a Quickshell shell can't do on its
// own, in one small program. The shell starts it with the session
// (shell/services/Spored.qml) and starts it again if it ends.
//
// It offers org.freedesktop.FileManager1 (filemanager.go), so a browser's
// "Show in folder" opens Spore Files; it locks the screen before the system
// sleeps (logind.go); and it tells the shell when a drive comes, goes or is
// mounted (drives.go). It talks to the shell in JSON lines (service.go).
// `spored files` is something else: the engine of Files' operations, which
// Files starts as its child (files.go).
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
	// `spored files`: Files' engine, on stdin and stdout (files.go).
	if len(os.Args) > 1 && os.Args[1] == "files" {
		filesMain()
		return
	}
	files := flag.String("files", "", "the spore-files command (default: from PATH)")
	nested := flag.Bool("nested", false, "a nested test session: only the drives (its session bus and logind are the real session's)")
	flag.Parse()

	svc := newService(os.Stdout)
	var offered []string

	// The real session only: in a nested one, the name would open Files
	// there, and logind's sleep is the real session's.
	if !*nested {
		session, err := dbus.ConnectSessionBus()
		if err != nil {
			log.Fatalf("no session bus: %v", err)
		}
		defer session.Close()
		if err := serveFileManager(session, filesCommand(*files)); err != nil {
			log.Fatal(err)
		}
		offered = append(offered, "filemanager")
		go func() {
			<-session.Context().Done()
			log.Fatal("the session bus closed")
		}()
	}

	// logind and UDisks2 are on the system bus. Without it, neither: the
	// shell goes on with its scripts for them.
	if system, err := dbus.ConnectSystemBus(); err != nil {
		log.Printf("no system bus, so no logind or drives: %v", err)
	} else {
		defer system.Close()
		var watch *logindWatch
		if !*nested {
			if watch, err = watchLogind(system, svc.event); err != nil {
				log.Printf("logind: %v", err)
			} else {
				offered = append(offered, "logind")
				svc.onLocked = watch.locked
			}
		}
		drives, err := watchDrives(system, svc.event)
		if err != nil {
			log.Printf("drives: %v", err)
		} else {
			offered = append(offered, "drives")
		}
		signals := make(chan *dbus.Signal, 64)
		system.Signal(signals)
		go func() {
			for s := range signals {
				if watch != nil {
					watch.signal(s)
				}
				if drives != nil {
					drives.signal(s)
				}
			}
		}()
		go func() {
			<-system.Context().Done()
			log.Fatal("the system bus closed")
		}()
	}

	svc.hello(offered)
	go svc.read(os.Stdin)

	// Until the shell stops it, or a bus goes away.
	stop := make(chan os.Signal, 1)
	signal.Notify(stop, syscall.SIGTERM, syscall.SIGINT)
	<-stop
}
