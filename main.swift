// Kilit — Mac için iki mod:
//  1) Giriş kilidi: fiziksel klavye, fare, touchpad kilitlenir; Claude gibi programların
//     gönderdiği sentetik tıklama/tuşlar geçmeye devam eder. Açmak: Touch ID (ya da PIN yaz + Enter).
//  2) Tek uygulama (Denetimli Erişim): seçilen uygulamaya kilitler. Çıkış: Esc ×3 → PIN.
import Cocoa
import SwiftUI
import LocalAuthentication

enum Mod { case yok, giris, uygulama }

// MARK: - Kurulum verisi
final class Durum: ObservableObject {
    @Published var mod: Mod = .giris
    @Published var uygulamalar: [NSRunningApplication] = []
    @Published var secili: pid_t? = nil
    @Published var pin = ""
    @Published var pin2 = ""
    @Published var sureDk = 0
    @Published var izinVar = AXIsProcessTrusted()
    @Published var touchIDVar = false

    func yenile() {
        izinVar = AXIsProcessTrusted()
        var e: NSError?
        touchIDVar = LAContext().canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e)
        let liste = NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && $0.processIdentifier != getpid() }
            .sorted { ($0.localizedName ?? "").localizedCaseInsensitiveCompare($1.localizedName ?? "") == .orderedAscending }
        if liste.map(\.processIdentifier) != uygulamalar.map(\.processIdentifier) { uygulamalar = liste }
    }

    var pinTamam: Bool { pin.count >= 4 && pin == pin2 && pin.allSatisfy(\.isNumber) }
    var hazir: Bool {
        guard izinVar, pinTamam else { return false }
        return mod == .giris || secili != nil
    }
}

// MARK: - Kurulum ekranı
struct KurulumView: View {
    @ObservedObject var d: Durum
    var baslat: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 12) {
                Image(systemName: "lock.shield.fill").font(.system(size: 34)).foregroundStyle(.blue)
                VStack(alignment: .leading) {
                    Text("Kilit").font(.title.bold())
                    Text("Mac'i senin yerine kilitler.").foregroundStyle(.secondary)
                }
            }

            if !d.izinVar {
                HStack {
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange)
                    Text("Önce Erişilebilirlik izni lazım (Ayarlar'da Kilit'i aç).")
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer()
                    Button("İzin ver") {
                        let o = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
                        _ = AXIsProcessTrustedWithOptions(o)
                    }
                }
                .padding(10).background(.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }

            Picker("", selection: $d.mod) {
                Text("Klavye + fare kilidi").tag(Mod.giris)
                Text("Tek uygulama").tag(Mod.uygulama)
            }
            .pickerStyle(.segmented).labelsHidden()

            if d.mod == .giris {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Klavye, fare ve touchpad kilitlenir.", systemImage: "keyboard")
                    Label("Claude arkada çalışmaya devam eder (⌘Tab, tıklama…).", systemImage: "sparkles")
                    Label(d.touchIDVar ? "Açmak: herhangi bir tuşa bas → Touch ID'ye parmağını koy."
                                       : "Touch ID bulunamadı: PIN'i yaz + Enter.", systemImage: "touchid")
                    Label("Yedek: PIN'i körlemesine yaz + Enter.", systemImage: "number")
                }
                .font(.callout).foregroundStyle(.secondary)
            } else {
                Text("Kilitlenecek uygulama").font(.headline)
                List(selection: $d.secili) {
                    ForEach(d.uygulamalar, id: \.processIdentifier) { app in
                        HStack {
                            Image(nsImage: app.icon ?? NSImage()).resizable().frame(width: 22, height: 22)
                            Text(app.localizedName ?? "?")
                        }
                        .tag(Optional(app.processIdentifier))
                    }
                }
                .frame(height: 180)
                .clipShape(RoundedRectangle(cornerRadius: 8))

                Text("Süre sınırı").font(.headline)
                Picker("", selection: $d.sureDk) {
                    Text("Sınırsız").tag(0); Text("5 dk").tag(5); Text("15 dk").tag(15)
                    Text("30 dk").tag(30); Text("1 saat").tag(60)
                }
                .pickerStyle(.segmented).labelsHidden()
                Text("Çıkmak için: Esc'ye hızlıca 3 kez bas → PIN gir.").font(.callout).foregroundStyle(.secondary)
            }

            Text(d.mod == .giris ? "Yedek PIN (en az 4 rakam)" : "PIN (en az 4 rakam)").font(.headline)
            HStack {
                SecureField("PIN", text: $d.pin)
                SecureField("PIN tekrar", text: $d.pin2)
            }
            .textFieldStyle(.roundedBorder)
            if !d.pin2.isEmpty && d.pin != d.pin2 {
                Text("PIN'ler aynı değil").font(.caption).foregroundStyle(.red)
            }

            Button(action: baslat) {
                Label("Kilitle", systemImage: "lock.fill").frame(maxWidth: .infinity)
            }
            .controlSize(.large).buttonStyle(.borderedProminent)
            .keyboardShortcut(.defaultAction)
            .disabled(!d.hazir)
        }
        .padding(22)
        .frame(width: 440)
    }
}

// MARK: - Ekrandaki küçük "kilitli" rozeti
final class RozetDurum: ObservableObject { @Published var yazi = "" }

struct RozetView: View {
    @ObservedObject var r: RozetDurum
    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "lock.fill")
            Text(r.yazi).lineLimit(1)
        }
        .font(.system(size: 13, weight: .semibold))
        .foregroundStyle(.white)
        .padding(.horizontal, 14).padding(.vertical, 7)
        .background(Capsule().fill(.black.opacity(0.75)))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .animation(.easeInOut(duration: 0.2), value: r.yazi)
    }
}

// MARK: - PIN ekranı (tek uygulama modu)
struct PinView: View {
    var sureDoldu: Bool
    var dene: (String) -> Bool
    var vazgec: () -> Void
    @State private var giris = ""
    @State private var mesaj = ""
    @State private var yanlisSayisi = 0
    @State private var bekle = false
    @FocusState private var odak: Bool

    var body: some View {
        VStack(spacing: 14) {
            Image(systemName: sureDoldu ? "hourglass" : "lock.fill").font(.system(size: 42))
            Text(sureDoldu ? "Süre doldu" : "Denetimli Erişim").font(.title2.bold())
            Text("Devam etmek için PIN gir").foregroundStyle(.secondary)
            SecureField("PIN", text: $giris)
                .textFieldStyle(.roundedBorder).frame(width: 200)
                .focused($odak).disabled(bekle).onSubmit(gonder)
            Text(mesaj).font(.callout).foregroundStyle(.red).frame(height: 16)
            HStack {
                if !sureDoldu { Button("Vazgeç", action: vazgec) }
                Button("Kilidi aç", action: gonder).keyboardShortcut(.defaultAction).disabled(bekle)
            }
        }
        .padding(32).frame(width: 340)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 18))
        .onAppear { odak = true }
    }

    func gonder() {
        if dene(giris) { return }
        giris = ""; yanlisSayisi += 1
        if yanlisSayisi % 3 == 0 {
            bekle = true; mesaj = "Çok fazla deneme. 30 sn bekle."
            DispatchQueue.main.asyncAfter(deadline: .now() + 30) { bekle = false; mesaj = ""; odak = true }
        } else { mesaj = "Yanlış PIN" }
    }
}

final class AnahtarPencere: NSWindow {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

// MARK: - Uygulama
final class Kilitci: NSObject, NSApplicationDelegate {
    let d = Durum()
    let rozetDurum = RozetDurum()
    var kurulum: NSWindow!
    var rozet: NSWindow?
    var pinPencere: NSWindow?
    var mod: Mod = .yok
    var hedef: NSRunningApplication?
    var hedefURL: URL?
    var pin = ""
    var tap: CFMachPort?
    var tapKaynak: CFRunLoopSource?
    var escZamanlari: [Date] = []
    var sureSayaci: Timer?
    // giriş kilidi
    var dogrulaniyor = false
    var sonDeneme = Date.distantPast
    var pinTampon = ""
    var sonTus = Date.distantPast
    var yanlisPin = 0
    var pinBekle = Date.distantPast

    func applicationDidFinishLaunching(_ n: Notification) {
        kurulum = NSWindow(contentRect: .zero, styleMask: [.titled, .closable, .miniaturizable],
                           backing: .buffered, defer: false)
        kurulum.title = "Kilit"
        kurulum.isReleasedWhenClosed = false
        kurulum.contentView = NSHostingView(rootView: KurulumView(d: d, baslat: { [weak self] in self?.kilitle() }))
        kurulum.setContentSize(NSSize(width: 440, height: 560))
        kurulum.center()
        kurulum.makeKeyAndOrderFront(nil)
        NSApp.activate()

        d.yenile()
        if !AXIsProcessTrusted() {   // izin yoksa sistem penceresini kendiliğinden aç
            let o = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
            _ = AXIsProcessTrustedWithOptions(o)
        }
        Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            guard let self, self.mod == .yok else { return }
            self.d.yenile()
        }
        let nc = NSWorkspace.shared.notificationCenter
        nc.addObserver(self, selector: #selector(aktiflesti(_:)), name: NSWorkspace.didActivateApplicationNotification, object: nil)
        nc.addObserver(self, selector: #selector(kapandi(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
    }

    func applicationShouldHandleReopen(_ s: NSApplication, hasVisibleWindows: Bool) -> Bool {
        if mod == .yok { kurulum.makeKeyAndOrderFront(nil) }
        return true
    }
    func applicationShouldTerminate(_ s: NSApplication) -> NSApplication.TerminateReply { mod == .yok ? .terminateNow : .terminateCancel }

    // MARK: Kilitle / aç
    func kilitle() {
        guard d.hazir, tapKur() else { d.izinVar = AXIsProcessTrusted(); return }
        pin = d.pin
        d.pin = ""; d.pin2 = ""
        pinTampon = ""; yanlisPin = 0

        if d.mod == .giris {
            mod = .giris
            kurulum.orderOut(nil)
            NSApp.hide(nil)                       // odak arkadaki uygulamaya (Claude'un çalıştığı yere) döner
            rozetGoster(d.touchIDVar ? "Kilitli · bir tuşa bas, Touch ID ile aç" : "Kilitli · PIN yaz + Enter")
            return
        }

        guard let pid = d.secili, let app = NSRunningApplication(processIdentifier: pid) else { return }
        mod = .uygulama
        hedef = app; hedefURL = app.bundleURL
        for a in NSWorkspace.shared.runningApplications
        where a.activationPolicy == .regular && a.processIdentifier != pid && a.processIdentifier != getpid() { a.hide() }
        kurulum.orderOut(nil)
        hedefeDon()
        NSApp.hide(nil)
        if d.sureDk > 0 {
            sureSayaci = Timer.scheduledTimer(withTimeInterval: TimeInterval(d.sureDk * 60), repeats: false) { [weak self] _ in
                self?.pinGoster(sureDoldu: true)
            }
        }
    }

    func kilidiAc() {
        let eskiMod = mod
        mod = .yok
        sureSayaci?.invalidate(); sureSayaci = nil
        pinPencere?.orderOut(nil); pinPencere = nil
        if let t = tap { CGEvent.tapEnable(tap: t, enable: false) }
        if let k = tapKaynak { CFRunLoopRemoveSource(CFRunLoopGetMain(), k, .commonModes) }
        tap = nil; tapKaynak = nil
        hedef = nil
        d.yenile()
        if eskiMod == .giris {
            rozetDurum.yazi = "Kilit açıldı"
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.2) { [weak self] in
                guard let self, self.mod == .yok else { return }
                self.rozet?.orderOut(nil); self.rozet = nil
            }
            // Kurulum penceresini öne getirmiyoruz: Claude çalışıyorsa odağını bozmasın. Dock'tan açılır.
        } else {
            NSApp.unhide(nil)
            kurulum.makeKeyAndOrderFront(nil)
            NSApp.activate()
        }
    }

    // MARK: Rozet
    func rozetGoster(_ yazi: String) {
        rozetDurum.yazi = yazi
        if rozet == nil {
            let ekran = NSScreen.main?.frame ?? .zero
            let gen: CGFloat = 420, yuk: CGFloat = 40
            let ust = NSScreen.main?.visibleFrame.maxY ?? ekran.maxY
            let w = NSWindow(contentRect: NSRect(x: ekran.midX - gen / 2, y: ust - yuk - 6, width: gen, height: yuk),
                             styleMask: [.borderless], backing: .buffered, defer: false)
            w.isOpaque = false
            w.backgroundColor = .clear
            w.level = .statusBar
            w.ignoresMouseEvents = true           // Claude'un tıklamaları rozetin içinden geçer
            w.sharingType = .none                 // ekran görüntülerine girmemesi için (sistem izin verirse)
            w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary, .ignoresCycle]
            w.contentView = NSHostingView(rootView: RozetView(r: rozetDurum))
            rozet = w
        }
        rozet?.orderFrontRegardless()
    }

    // MARK: Touch ID
    func touchIDiste() {
        guard mod == .giris, !dogrulaniyor, Date().timeIntervalSince(sonDeneme) > 1.5 else { return }
        let c = LAContext()
        c.localizedFallbackTitle = ""             // "Parola gir" seçeneği çıkmasın (klavye kilitli)
        var e: NSError?
        guard c.canEvaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, error: &e) else {
            rozetGoster("Touch ID kullanılamıyor · PIN yaz + Enter")
            return
        }
        dogrulaniyor = true
        sonDeneme = Date()
        rozetGoster("Parmağını Touch ID'ye koy")
        c.evaluatePolicy(.deviceOwnerAuthenticationWithBiometrics, localizedReason: "klavye ve fare kilidini açmak") { [weak self] ok, _ in
            DispatchQueue.main.async {
                guard let self else { return }
                self.dogrulaniyor = false
                self.sonDeneme = Date()
                guard self.mod == .giris else { return }
                if ok { self.kilidiAc() } else { self.rozetGoster("Açılmadı · tekrar bir tuşa bas") }
            }
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 20) { [weak self] in
            if self?.dogrulaniyor == true { c.invalidate() }
        }
    }

    // Körlemesine PIN: fiziksel tuşlar yutulur ama burada okunur
    func pinTusu(_ e: CGEvent) {
        let kod = e.getIntegerValueField(.keyboardEventKeycode)
        let simdi = Date()
        if simdi.timeIntervalSince(sonTus) > 6 { pinTampon = "" }
        sonTus = simdi
        if kod == 36 || kod == 76 {               // Enter
            defer { pinTampon = "" }
            guard !pinTampon.isEmpty else { return }
            if simdi < pinBekle { rozetGoster("Çok fazla deneme · biraz bekle"); return }
            if pinTampon == pin { kilidiAc(); return }
            yanlisPin += 1
            if yanlisPin % 3 == 0 { pinBekle = simdi.addingTimeInterval(30) }
            rozetGoster("Yanlış PIN")
            return
        }
        if kod == 51 || kod == 53 { pinTampon = ""; return }   // sil / Esc → temizle
        var uz = 0
        var harf = [UniChar](repeating: 0, count: 4)
        e.keyboardGetUnicodeString(maxStringLength: 4, actualStringLength: &uz, unicodeString: &harf)
        let s = String(utf16CodeUnits: harf, count: uz)
        if s.count == 1, s.first!.isNumber { pinTampon += s; if pinTampon.count > 12 { pinTampon.removeFirst() } }
    }

    // MARK: Tek uygulama modu
    func hedefeDon() {
        guard mod == .uygulama, pinPencere == nil else { return }
        if let url = hedefURL {
            let c = NSWorkspace.OpenConfiguration(); c.activates = true
            NSWorkspace.shared.openApplication(at: url, configuration: c) { [weak self] app, _ in
                if let app { DispatchQueue.main.async { self?.hedef = app } }
            }
        } else { hedef?.activate() }
    }

    @objc func aktiflesti(_ n: Notification) {
        guard mod == .uygulama, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
        if app.processIdentifier == hedef?.processIdentifier { return }
        if app.processIdentifier == getpid() { if pinPencere == nil { pinGoster(sureDoldu: false) }; return }
        if pinPencere != nil { return }
        app.hide()
        hedefeDon()
    }

    @objc func kapandi(_ n: Notification) {
        guard mod == .uygulama, let app = n.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.processIdentifier == hedef?.processIdentifier else { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in self?.hedefeDon() }
    }

    func pinGoster(sureDoldu: Bool) {
        guard mod == .uygulama else { return }
        if let p = pinPencere {
            if !sureDoldu { p.makeKeyAndOrderFront(nil); NSApp.activate(); return }
            p.orderOut(nil); pinPencere = nil
        }
        let ekran = NSScreen.main?.frame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let view = PinView(
            sureDoldu: sureDoldu,
            dene: { [weak self] g in
                guard let self, g == self.pin else { return false }
                DispatchQueue.main.async { self.kilidiAc() }
                return true
            },
            vazgec: { [weak self] in
                guard let self else { return }
                self.pinPencere?.orderOut(nil); self.pinPencere = nil
                NSApp.hide(nil); self.hedefeDon()
            })
        let kok = ZStack { Color.black.opacity(sureDoldu ? 0.92 : 0.35); view }
        let w = AnahtarPencere(contentRect: ekran, styleMask: [.borderless], backing: .buffered, defer: false)
        w.isOpaque = false; w.backgroundColor = .clear; w.level = .screenSaver
        w.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        w.contentView = NSHostingView(rootView: kok)
        w.setFrame(ekran, display: true)
        pinPencere = w
        NSApp.unhide(nil); NSApp.activate()
        w.makeKeyAndOrderFront(nil)
    }

    // MARK: Olay yakalayıcı
    func tapKur() -> Bool {
        if tap != nil { return true }
        let maske = CGEventMask.max               // tüm olaylar: tuş, tık, hareket, kaydırma, touchpad hareketleri
        let t = CGEvent.tapCreate(tap: .cghidEventTap, place: .headInsertEventTap, options: .defaultTap,
                                  eventsOfInterest: maske, callback: tapGeriCagri, userInfo: nil)
              ?? CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap,
                                   eventsOfInterest: maske, callback: tapGeriCagri, userInfo: nil)
        guard let t else { return false }
        let k = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, t, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), k, .commonModes)
        CGEvent.tapEnable(tap: t, enable: true)
        tap = t; tapKaynak = k
        return true
    }

    /// true → olay yutulur.
    func engelle(_ type: CGEventType, _ e: CGEvent) -> Bool {
        switch mod {
        case .yok:
            return false

        case .giris:
            // Gerçek donanımdan gelen olaylarda gönderen işlem numarası 0'dır.
            // Claude ve diğer programların gönderdiği olaylar kendi numarasını taşır → geçer.
            guard e.getIntegerValueField(.eventSourceUnixProcessID) == 0 else { return false }
            switch type {
            case .keyDown:
                if e.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                    pinTusu(e)
                    DispatchQueue.main.async { self.touchIDiste() }
                }
            case .leftMouseDown, .rightMouseDown, .otherMouseDown:
                DispatchQueue.main.async { self.touchIDiste() }
            default: break
            }
            return true

        case .uygulama:
            guard type == .keyDown else { return false }
            let kod = e.getIntegerValueField(.keyboardEventKeycode)
            let f = e.flags
            let cmd = f.contains(.maskCommand), ctrl = f.contains(.maskControl), opt = f.contains(.maskAlternate)
            if cmd && [48, 12, 4, 46, 50, 49, 53].contains(kod) { return true }   // ⌘Tab ⌘Q ⌘H ⌘M ⌘` ⌘Boşluk ⌘⌥Esc
            if cmd && opt && kod == 2 { return true }
            if ctrl && [123, 124, 125, 126].contains(kod) { return true }
            if [160, 131, 130, 177].contains(kod) { return true }
            if kod == 53 && !cmd && !ctrl && !opt && pinPencere == nil
                && e.getIntegerValueField(.keyboardEventAutorepeat) == 0 {
                let simdi = Date()
                escZamanlari = escZamanlari.filter { simdi.timeIntervalSince($0) < 1.5 } + [simdi]
                if escZamanlari.count >= 3 {
                    escZamanlari = []
                    DispatchQueue.main.async { self.pinGoster(sureDoldu: false) }
                    return true
                }
            }
            return false
        }
    }
}

var kilitci: Kilitci!

func tapGeriCagri(proxy: CGEventTapProxy, type: CGEventType, event: CGEvent, refcon: UnsafeMutableRawPointer?) -> Unmanaged<CGEvent>? {
    if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
        if let t = kilitci.tap { CGEvent.tapEnable(tap: t, enable: true) }
        return Unmanaged.passUnretained(event)
    }
    return kilitci.engelle(type, event) ? nil : Unmanaged.passUnretained(event)
}

let uygulama = NSApplication.shared
kilitci = Kilitci()
uygulama.delegate = kilitci
uygulama.setActivationPolicy(.regular)
uygulama.run()
