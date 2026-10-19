package main

// The KDE Connect daemon (kdeconnectd) over the session bus: the same
// interfaces kdeconnect-cli and the shell's KdeConnect.qml use. Signatures
// are KDE Connect 26.08's (plugins/sms, plugins/notifications, core/device).

import (
	"context"
	"errors"
	"fmt"
	"slices"
	"sort"
	"strings"
	"time"

	"github.com/godbus/dbus/v5"
)

const (
	service    = "org.kde.kdeconnect"
	daemonPath = dbus.ObjectPath("/modules/kdeconnect")
	daemonIf   = "org.kde.kdeconnect.daemon"
	deviceIf   = "org.kde.kdeconnect.device"
	convIf     = "org.kde.kdeconnect.device.conversations"
	notifIf    = "org.kde.kdeconnect.device.notifications"
	notifObjIf = "org.kde.kdeconnect.device.notifications.notification"
	callTO     = 10 * time.Second
)

type KDEConnect struct {
	conn *dbus.Conn
}

type Device struct {
	ID        string   `json:"id"`
	Name      string   `json:"name"`
	Type      string   `json:"type,omitempty"`
	Reachable bool     `json:"reachable"`
	Battery   *Battery `json:"battery,omitempty"`
	Can       []string `json:"can"`
}

type Battery struct {
	Charge   int32 `json:"charge"`
	Charging bool  `json:"charging"`
}

// What the plugins loaded on a device let the tools do.
var pluginTools = map[string]string{
	"kdeconnect_sms":           "sms",
	"kdeconnect_share":         "share",
	"kdeconnect_clipboard":     "clipboard",
	"kdeconnect_findmyphone":   "ring",
	"kdeconnect_ping":          "ping",
	"kdeconnect_notifications": "notifications",
}

func devicePath(id string) dbus.ObjectPath {
	return dbus.ObjectPath("/modules/kdeconnect/devices/" + id)
}

func (k *KDEConnect) call(ctx context.Context, path dbus.ObjectPath, iface, method string, args ...any) *dbus.Call {
	ctx, cancel := context.WithTimeout(ctx, callTO)
	defer cancel()
	return k.conn.Object(service, path).CallWithContext(ctx, iface+"."+method, 0, args...)
}

// getAll reads every property of an interface, with call's timeout.
func (k *KDEConnect) getAll(ctx context.Context, path dbus.ObjectPath, iface string) (map[string]dbus.Variant, error) {
	props := map[string]dbus.Variant{}
	err := k.call(ctx, path, "org.freedesktop.DBus.Properties", "GetAll", iface).Store(&props)
	return props, err
}

func unreachable(err error) error {
	var dbusErr dbus.Error
	if errors.As(err, &dbusErr) && dbusErr.Name == "org.freedesktop.DBus.Error.ServiceUnknown" {
		return errors.New("KDE Connect isn't running on this computer (kdeconnectd)")
	}
	return err
}

// Devices returns the paired devices, reachable ones first.
func (k *KDEConnect) Devices(ctx context.Context) ([]Device, error) {
	var ids []string
	if err := k.call(ctx, daemonPath, daemonIf, "devices", false, true).Store(&ids); err != nil {
		return nil, unreachable(err)
	}
	out := make([]Device, 0, len(ids))
	for _, id := range ids {
		p := devicePath(id)
		props, err := k.getAll(ctx, p, deviceIf)
		if err != nil {
			continue
		}
		d := Device{ID: id, Can: []string{}}
		d.Name, _ = props["name"].Value().(string)
		d.Type, _ = props["type"].Value().(string)
		d.Reachable, _ = props["isReachable"].Value().(bool)
		if d.Reachable {
			var loaded []string
			_ = k.call(ctx, p, deviceIf, "loadedPlugins").Store(&loaded)
			for _, pl := range loaded {
				if t, ok := pluginTools[pl]; ok {
					d.Can = append(d.Can, t)
				}
			}
			sort.Strings(d.Can)
			if slices.Contains(loaded, "kdeconnect_battery") {
				bat, err := k.getAll(ctx, p+"/battery", "org.kde.kdeconnect.device.battery")
				c, okC := bat["charge"]
				ch, okCh := bat["isCharging"]
				if err == nil && okC && okCh {
					charge, _ := c.Value().(int32)
					charging, _ := ch.Value().(bool)
					if charge >= 0 {
						d.Battery = &Battery{Charge: charge, Charging: charging}
					}
				}
			}
		}
		out = append(out, d)
	}
	sort.SliceStable(out, func(i, j int) bool { return out[i].Reachable && !out[j].Reachable })
	return out, nil
}

// Pick finds the device a tool acts on: the one named (id or name), else
// the only reachable one able to do `can`.
func (k *KDEConnect) Pick(ctx context.Context, want, can string) (Device, error) {
	devs, err := k.Devices(ctx)
	if err != nil {
		return Device{}, err
	}
	if len(devs) == 0 {
		return Device{}, errors.New("no device is paired with KDE Connect")
	}
	if want != "" {
		for _, d := range devs {
			if d.ID == want || strings.EqualFold(d.Name, want) {
				if !d.Reachable {
					return Device{}, fmt.Errorf("%s isn't reachable now (same network, KDE Connect running on it?)", d.Name)
				}
				if !slices.Contains(d.Can, can) {
					return Device{}, fmt.Errorf("%s can't do %s (its KDE Connect plugin is off or missing)", d.Name, can)
				}
				return d, nil
			}
		}
		return Device{}, fmt.Errorf("no paired device %q (there are: %s)", want, names(devs))
	}
	var ok []Device
	for _, d := range devs {
		if d.Reachable && slices.Contains(d.Can, can) {
			ok = append(ok, d)
		}
	}
	switch len(ok) {
	case 1:
		return ok[0], nil
	case 0:
		return Device{}, fmt.Errorf("no reachable device can do %s now (paired: %s)", can, names(devs))
	}
	return Device{}, fmt.Errorf("several devices can do %s: say which (%s)", can, names(ok))
}

func names(devs []Device) string {
	s := make([]string, len(devs))
	for i, d := range devs {
		s[i] = d.Name
		if !d.Reachable {
			s[i] += " (unreachable)"
		}
	}
	return strings.Join(s, ", ")
}

// address is ConversationAddress on the bus: a struct of one string.
type address struct{ Address string }

func (k *KDEConnect) SendSMS(ctx context.Context, id string, to []string, text string) error {
	addrs := make([]dbus.Variant, len(to))
	for i, a := range to {
		addrs[i] = dbus.MakeVariant(address{a})
	}
	// sendSms(av addresses, s text, av attachments): subID left to its default.
	return k.call(ctx, devicePath(id)+"/sms", "org.kde.kdeconnect.device.sms", "sendSms", addrs, text, []dbus.Variant{}).Err
}

func (k *KDEConnect) ShareURL(ctx context.Context, id, url string) error {
	return k.call(ctx, devicePath(id)+"/share", "org.kde.kdeconnect.device.share", "shareUrl", url).Err
}

func (k *KDEConnect) ShareText(ctx context.Context, id, text string) error {
	return k.call(ctx, devicePath(id)+"/share", "org.kde.kdeconnect.device.share", "shareText", text).Err
}

func (k *KDEConnect) SetClipboard(ctx context.Context, id, text string) error {
	// sendClipboard(v): a string (a URL would send a file).
	return k.call(ctx, devicePath(id)+"/clipboard", "org.kde.kdeconnect.device.clipboard", "sendClipboard", dbus.MakeVariant(text)).Err
}

func (k *KDEConnect) Ring(ctx context.Context, id string) error {
	return k.call(ctx, devicePath(id)+"/findmyphone", "org.kde.kdeconnect.device.findmyphone", "ring").Err
}

func (k *KDEConnect) Ping(ctx context.Context, id, msg string) error {
	if msg == "" {
		return k.call(ctx, devicePath(id)+"/ping", "org.kde.kdeconnect.device.ping", "sendPing").Err
	}
	return k.call(ctx, devicePath(id)+"/ping", "org.kde.kdeconnect.device.ping", "sendPing", msg).Err
}

// Message is ConversationMessage: (i s a(s) x i i x i x a(xsss)).
type Message struct {
	Event       int32
	Body        string
	Addresses   []address
	Date        int64
	Type        int32
	Read        int32
	ThreadID    int64
	UID         int32
	SubID       int64
	Attachments []attachment
}

type attachment struct {
	PartID   int64
	MimeType string
	Base64   string
	UniqueID string
}

func toMessage(v any) (Message, bool) {
	if dv, ok := v.(dbus.Variant); ok {
		v = dv.Value()
	}
	fields, ok := v.([]any)
	if !ok {
		return Message{}, false
	}
	var m Message
	if err := dbus.Store(fields, &m.Event, &m.Body, &m.Addresses, &m.Date, &m.Type, &m.Read, &m.ThreadID, &m.UID, &m.SubID, &m.Attachments); err != nil {
		return Message{}, false
	}
	return m, true
}

// signals subscribes to the conversation signals of a device until stop.
func (k *KDEConnect) signals(id string) (chan *dbus.Signal, func(), error) {
	opts := []dbus.MatchOption{dbus.WithMatchObjectPath(devicePath(id)), dbus.WithMatchInterface(convIf)}
	if err := k.conn.AddMatchSignal(opts...); err != nil {
		return nil, nil, err
	}
	ch := make(chan *dbus.Signal, 512)
	k.conn.Signal(ch)
	return ch, func() {
		k.conn.RemoveSignal(ch)
		_ = k.conn.RemoveMatchSignal(opts...)
	}, nil
}

// Conversations returns the latest message of each thread. The daemon
// caches them: the phone is asked for the threads, whose answers come as
// signals, waited for until they stop (quiet) or for at most wait.
func (k *KDEConnect) Conversations(ctx context.Context, id string, wait, quiet time.Duration) ([]Message, error) {
	ch, stop, err := k.signals(id)
	if err != nil {
		return nil, err
	}
	defer stop()
	if err := k.call(ctx, devicePath(id), convIf, "requestAllConversationThreads").Err; err != nil {
		return nil, err
	}
	collect(ctx, ch, wait, quiet, func(*dbus.Signal) bool { return false })
	var raw []dbus.Variant
	if err := k.call(ctx, devicePath(id), convIf, "activeConversations").Store(&raw); err != nil {
		return nil, err
	}
	out := make([]Message, 0, len(raw))
	for _, v := range raw {
		if m, ok := toMessage(v); ok {
			out = append(out, m)
		}
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date > out[j].Date })
	return out, nil
}

// Thread returns up to n of a thread's latest messages, oldest first.
func (k *KDEConnect) Thread(ctx context.Context, id string, thread int64, n int, wait, quiet time.Duration) ([]Message, error) {
	ch, stop, err := k.signals(id)
	if err != nil {
		return nil, err
	}
	defer stop()
	if err := k.call(ctx, devicePath(id), convIf, "requestConversation", thread, int32(0), int32(n)).Err; err != nil {
		return nil, err
	}
	seen := map[int32]Message{}
	collect(ctx, ch, wait, quiet, func(s *dbus.Signal) bool {
		if s.Name != convIf+".conversationUpdated" || len(s.Body) == 0 {
			return false
		}
		if m, ok := toMessage(s.Body[0]); ok && m.ThreadID == thread {
			seen[m.UID] = m
		}
		return len(seen) >= n
	})
	out := make([]Message, 0, len(seen))
	for _, m := range seen {
		out = append(out, m)
	}
	sort.Slice(out, func(i, j int) bool { return out[i].Date < out[j].Date })
	if len(out) > n {
		out = out[len(out)-n:]
	}
	return out, nil
}

// collect reads signals until done says so, none came for quiet (after
// the first), or wait is over.
func collect(ctx context.Context, ch chan *dbus.Signal, wait, quiet time.Duration, done func(*dbus.Signal) bool) {
	deadline := time.NewTimer(wait)
	defer deadline.Stop()
	var idle <-chan time.Time
	for {
		select {
		case s := <-ch:
			if done(s) {
				return
			}
			idle = time.After(quiet)
		case <-idle:
			return
		case <-deadline.C:
			return
		case <-ctx.Done():
			return
		}
	}
}

type Notification struct {
	ID       string `json:"id"`
	App      string `json:"app"`
	Title    string `json:"title,omitempty"`
	Text     string `json:"text,omitempty"`
	CanReply bool   `json:"can_reply,omitempty"`
	replyID  string
}

func (k *KDEConnect) Notifications(ctx context.Context, id string) ([]Notification, error) {
	var ids []string
	if err := k.call(ctx, devicePath(id)+"/notifications", notifIf, "activeNotifications").Store(&ids); err != nil {
		return nil, err
	}
	out := make([]Notification, 0, len(ids))
	for _, nid := range ids {
		p := devicePath(id) + "/notifications/" + dbus.ObjectPath(nid)
		if !p.IsValid() {
			continue
		}
		props, err := k.getAll(ctx, p, notifObjIf)
		if err != nil {
			continue
		}
		n := Notification{ID: nid}
		n.App, _ = props["appName"].Value().(string)
		n.Title, _ = props["title"].Value().(string)
		n.Text, _ = props["text"].Value().(string)
		n.replyID, _ = props["replyId"].Value().(string)
		n.CanReply = n.replyID != ""
		out = append(out, n)
	}
	return out, nil
}

func (k *KDEConnect) Reply(ctx context.Context, id, notification, text string) (Notification, error) {
	ns, err := k.Notifications(ctx, id)
	if err != nil {
		return Notification{}, err
	}
	for _, n := range ns {
		if n.ID != notification {
			continue
		}
		if !n.CanReply {
			return n, fmt.Errorf("the %s notification can't be answered from here", n.App)
		}
		return n, k.call(ctx, devicePath(id)+"/notifications", notifIf, "sendReply", n.replyID, text).Err
	}
	return Notification{}, fmt.Errorf("no notification %q on the phone now (list them again)", notification)
}
