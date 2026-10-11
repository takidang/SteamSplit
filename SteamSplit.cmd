<# :
@echo off
set "SELF=%~f0"
rem Chay an qua conhost (Windows Terminal khong an duoc cua so), roi dong cua so nay.
start "" conhost.exe powershell -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -Command "$s=[IO.File]::ReadAllText($env:SELF); iex $s.Substring($s.IndexOf('#'+'PS'+'#'))"
exit /b
#>
#PS#
# SteamSplit - mo Steam Store/Community khi bi chan, khong can admin, khong doi DNS/hosts.
# Cach lam: proxy noi bo (127.0.0.1) chi cho domain Steam; tu phan giai IP qua DoH 1.1.1.1;
# cat nho goi TLS ClientHello de lach bo loc SNI. Thoat la tra lai cai dat proxy cu.
# Chay an, chi co icon o khay he thong; chuot phai icon de test lai hoac tat.
# Khong co tu cap nhat, khong gui du lieu di dau ngoai Steam va 1.1.1.1.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Reg    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$Backup = Join-Path $env:LOCALAPPDATA 'SteamSplit-backup.json'
$IconFile = Join-Path (Split-Path $env:SELF) 'SteamSplit.ico'   # khong co thi dung icon khien cua Windows

Add-Type -TypeDefinition @'
using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Sockets;
using System.Runtime.InteropServices;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading;

namespace SteamSplit {
public class Proxy {
    public static readonly string[] Domains = {
        "steampowered.com", "steamcommunity.com", "steamstatic.com", "steam-chat.com",
        "steamusercontent.com", "steamgames.com", "steamcontent.com"
    };
    public int Port;
    public int Mode = 1; // 1: cat giua ten SNI, 2: cat sau byte dau, 3: ca hai
    TcpListener listener;
    static readonly Dictionary<string, IPAddress> cache = new Dictionary<string, IPAddress>();

    public Proxy(int port) { Port = port; }

    public void Start() {
        listener = new TcpListener(IPAddress.Loopback, Port);
        listener.Start();
        Thread t = new Thread(AcceptLoop);
        t.IsBackground = true;
        t.Start();
    }

    public void Stop() { try { listener.Stop(); } catch { } }

    public static bool Allowed(string host) {
        host = host.ToLowerInvariant();
        foreach (string d in Domains) if (host == d || host.EndsWith("." + d)) return true;
        return false;
    }

    public string Pac() {
        return "function FindProxyForURL(url, host) {\n" +
               "  if (url.substring(0, 5) == \"http:\") return \"DIRECT\";\n" +
               "  var d = [\"" + string.Join("\",\"", Domains) + "\"];\n" +
               "  for (var i = 0; i < d.length; i++)\n" +
               "    if (host == d[i] || dnsDomainIs(host, \".\" + d[i])) return \"PROXY 127.0.0.1:" + Port + "; DIRECT\";\n" +
               "  return \"DIRECT\";\n}\n";
    }

    [DllImport("wininet.dll")]
    static extern bool InternetSetOption(IntPtr h, int option, IntPtr buf, int len);
    public static void RefreshSystemProxy() {
        InternetSetOption(IntPtr.Zero, 39, IntPtr.Zero, 0); // SETTINGS_CHANGED
        InternetSetOption(IntPtr.Zero, 37, IntPtr.Zero, 0); // REFRESH
    }

    void AcceptLoop() {
        while (true) {
            TcpClient c;
            try { c = listener.AcceptTcpClient(); } catch { return; }
            ThreadPool.QueueUserWorkItem(Handle, c);
        }
    }

    // Phan giai qua DoH (tranh DNS bi nha mang lam gia), loi thi dung DNS he thong.
    static IPAddress Resolve(string host) {
        IPAddress ip;
        if (IPAddress.TryParse(host, out ip)) return ip;
        lock (cache) { if (cache.TryGetValue(host, out ip)) return ip; }
        try {
            HttpWebRequest r = (HttpWebRequest)WebRequest.Create(
                "https://1.1.1.1/dns-query?type=A&name=" + Uri.EscapeDataString(host));
            r.Accept = "application/dns-json";
            r.Timeout = 4000;
            r.Proxy = null;
            using (WebResponse resp = r.GetResponse())
            using (StreamReader sr = new StreamReader(resp.GetResponseStream())) {
                Match m = Regex.Match(sr.ReadToEnd(), "\"data\":\\s*\"(\\d+\\.\\d+\\.\\d+\\.\\d+)\"");
                if (m.Success) ip = IPAddress.Parse(m.Groups[1].Value);
            }
        } catch { }
        if (ip == null) {
            // Bo qua IP gia nha mang hay tra (127.x, 0.0.0.0) de khong noi vao chinh may minh
            foreach (IPAddress a in Dns.GetHostAddresses(host))
                if (a.AddressFamily == AddressFamily.InterNetwork && !IPAddress.IsLoopback(a)
                    && !a.Equals(IPAddress.Any)) { ip = a; break; }
        }
        if (ip == null) throw new Exception("Khong phan giai duoc " + host);
        lock (cache) { cache[host] = ip; }
        return ip;
    }

    static string ReadRequestLine(NetworkStream s) {
        byte[] b = new byte[8192];
        int len = 0;
        while (len < b.Length) {
            int n = s.Read(b, len, b.Length - len);
            if (n <= 0) return null;
            len += n;
            string t = Encoding.ASCII.GetString(b, 0, len);
            if (t.Contains("\r\n\r\n")) return t.Substring(0, t.IndexOf("\r\n"));
        }
        return null;
    }

    static void Reply(Stream s, string status, string type, byte[] body) {
        byte[] h = Encoding.ASCII.GetBytes("HTTP/1.1 " + status + "\r\nContent-Type: " + type +
            "\r\nContent-Length: " + body.Length + "\r\nConnection: close\r\n\r\n");
        s.Write(h, 0, h.Length);
        s.Write(body, 0, body.Length);
    }

    // Vi tri bat dau ten mien trong extension SNI cua ClientHello, -1 neu khong thay.
    static int FindSni(byte[] d, int len, out int nameLen) {
        nameLen = 0;
        try {
            if (len < 43 || d[0] != 0x16 || d[5] != 0x01) return -1;
            int p = 5 + 4 + 2 + 32;                    // record hdr, handshake hdr, version, random
            p += 1 + d[p];                              // session id
            p += 2 + ((d[p] << 8) | d[p + 1]);          // cipher suites
            p += 1 + d[p];                              // compression
            int end = p + 2 + ((d[p] << 8) | d[p + 1]);
            p += 2;
            while (p + 4 <= end && p + 4 <= len) {
                int type = (d[p] << 8) | d[p + 1];
                int el = (d[p + 2] << 8) | d[p + 3];
                if (type == 0) {
                    int q = p + 4 + 2 + 1;              // list len, name type
                    nameLen = (d[q] << 8) | d[q + 1];
                    return q + 2;
                }
                p += 4 + el;
            }
        } catch { }
        return -1;
    }

    void SendSplit(NetworkStream ss, byte[] d, int len) {
        int nameLen;
        int sni = FindSni(d, len, out nameLen);
        int mid = (sni > 0 && nameLen > 1) ? sni + nameLen / 2 : 1;
        int[] cuts = Mode == 2 ? new int[] { 1 } : Mode == 3 ? new int[] { 1, mid } : new int[] { mid };
        int pos = 0;
        foreach (int c in cuts) {
            if (c <= pos || c >= len) continue;
            ss.Write(d, pos, c - pos);
            ss.Flush();
            Thread.Sleep(20);
            pos = c;
        }
        ss.Write(d, pos, len - pos);
    }

    static void Pump(Stream from, Stream to, TcpClient a, TcpClient b) {
        byte[] buf = new byte[32768];
        try { int n; while ((n = from.Read(buf, 0, buf.Length)) > 0) to.Write(buf, 0, n); } catch { }
        try { a.Close(); } catch { }
        try { b.Close(); } catch { }
    }

    void Handle(object state) {
        TcpClient client = (TcpClient)state;
        TcpClient server = null;
        try {
            client.NoDelay = true;
            client.ReceiveTimeout = 15000;
            NetworkStream cs = client.GetStream();
            string line = ReadRequestLine(cs);
            if (line == null) return;
            string[] parts = line.Split(' ');
            if (parts.Length < 2) return;

            if (parts[0] == "GET" && parts[1].StartsWith("/proxy.pac")) {
                Reply(cs, "200 OK", "application/x-ns-proxy-autoconfig", Encoding.ASCII.GetBytes(Pac()));
                return;
            }
            int colon = parts[1].LastIndexOf(':');
            if (parts[0] != "CONNECT" || colon < 1) { Reply(cs, "405 Method Not Allowed", "text/plain", new byte[0]); return; }
            string host = parts[1].Substring(0, colon);
            int port = int.Parse(parts[1].Substring(colon + 1));
            if (!Allowed(host)) { Reply(cs, "403 Forbidden", "text/plain", new byte[0]); return; }

            IPAddress ip = Resolve(host);
            server = new TcpClient(ip.AddressFamily);
            server.NoDelay = true;
            server.Connect(ip, port);
            byte[] ok = Encoding.ASCII.GetBytes("HTTP/1.1 200 Connection Established\r\n\r\n");
            cs.Write(ok, 0, ok.Length);

            NetworkStream ss = server.GetStream();
            byte[] first = new byte[16384];
            int fl = cs.Read(first, 0, first.Length);
            if (fl <= 0) return;
            if (first[0] == 0x16 && fl >= 5) {
                int need = 5 + ((first[3] << 8) | first[4]);
                while (fl < need && fl < first.Length) {
                    int n = cs.Read(first, fl, first.Length - fl);
                    if (n <= 0) break;
                    fl += n;
                }
                SendSplit(ss, first, fl);
            } else {
                ss.Write(first, 0, fl);
            }
            client.ReceiveTimeout = 0;

            TcpClient sv = server, cl = client;
            Thread t = new Thread(delegate() { Pump(ss, cs, sv, cl); });
            t.IsBackground = true;
            t.Start();
            Pump(cs, ss, cl, sv);
        } catch { }
        finally {
            try { client.Close(); } catch { }
            try { if (server != null) server.Close(); } catch { }
        }
    }
}
}
'@

Add-Type -AssemblyName System.Windows.Forms, System.Drawing
[Windows.Forms.Application]::EnableVisualStyles()

function Msg([string]$Text, [string]$Icon = 'Information') {
    [Windows.Forms.MessageBox]::Show($Text, 'SteamSplit', 'OK', $Icon) | Out-Null
}

# Tra ve @{ Ok = $true/$false; Text = 'tung dong ket qua' }
function Test-Steam([int]$Port = 0) {
    $lines = @()
    foreach ($u in 'https://store.steampowered.com/', 'https://steamcommunity.com/') {
        $a = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--max-time', '8')
        if ($Port) { $a += @('--proxy', "http://127.0.0.1:$Port") }
        $code = & curl.exe @a $u
        if (-not $code -or $code -eq '000') { return @{ Ok = $false; Text = (($lines + "[X] $u") -join "`n") } }
        $lines += "[OK] $u (HTTP $code)"
    }
    return @{ Ok = $true; Text = ($lines -join "`n") }
}

function Restore-Proxy {
    if (-not (Test-Path $Backup)) { return }
    $b = Get-Content $Backup -Raw | ConvertFrom-Json
    if ($b.Url) { Set-ItemProperty $Reg -Name AutoConfigURL -Value $b.Url }
    else        { Remove-ItemProperty $Reg -Name AutoConfigURL -ErrorAction SilentlyContinue }
    Remove-Item $Backup -Force
    [SteamSplit.Proxy]::RefreshSystemProxy()
}

# Chi cho chay mot ban: ban thu hai se khoi phuc cai dat trong khi ban dau con dang chay
$mutex = New-Object Threading.Mutex($false, 'Local\SteamSplit')
try { $first = $mutex.WaitOne(0) } catch [Threading.AbandonedMutexException] { $first = $true }
if (-not $first) {
    Msg 'SteamSplit dang chay roi. Xem icon o khay he thong (goc phai thanh taskbar, co the nam trong mui ten ^).'
    return
}

# Loi tat ngoai Desktop
$lnkPath = Join-Path ([Environment]::GetFolderPath('Desktop')) 'SteamSplit.lnk'
$noLnk   = Join-Path $env:LOCALAPPDATA 'SteamSplit-noshortcut'
function New-Shortcut {
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    $l.TargetPath = $env:SELF
    $l.WorkingDirectory = Split-Path $env:SELF
    if (Test-Path $IconFile) { $l.IconLocation = "$IconFile,0" }
    else { $l.IconLocation = "$env:SystemRoot\System32\imageres.dll,73" }
    $l.WindowStyle = 7
    $l.Description = 'Mo Steam Store/Community khi bi chan'
    $l.Save()
    Remove-Item $noLnk -ErrorAction SilentlyContinue
}

# Lan dau hoi mot lan; neu thu muc bi doi cho thi tu sua lai loi tat
try {
    if (Test-Path $lnkPath) {
        $old = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
        if ($old.TargetPath -ne $env:SELF -or ((Test-Path $IconFile) -and $old.IconLocation -ne "$IconFile,0")) { New-Shortcut }
    } elseif (-not (Test-Path $noLnk)) {
        $r = [Windows.Forms.MessageBox]::Show("Tao loi tat SteamSplit ngoai Desktop cho de tim?`n(Luc nao cung tao lai duoc: chuot phai icon o khay.)",
            'SteamSplit', 'YesNo', 'Question')
        if ($r -eq 'Yes') { New-Shortcut } else { Set-Content $noLnk '' }
    }
} catch { }

$tray = New-Object Windows.Forms.NotifyIcon
$tray.Icon = [Drawing.SystemIcons]::Shield
try { if (Test-Path $IconFile) { $tray.Icon = New-Object Drawing.Icon($IconFile, [Windows.Forms.SystemInformation]::SmallIconSize) } } catch { }
$tray.Text = 'SteamSplit: dang kiem tra...'
$tray.Visible = $true
$tray.ShowBalloonTip(3000, 'SteamSplit', 'Dang kiem tra ket noi Steam, doi chut...', 'Info')

$px = $null
try {
    Restore-Proxy   # lan truoc bi tat dot ngot thi don lai truoc

    if ((Test-Steam).Ok) {
        Msg 'Steam vao binh thuong, khong can bat SteamSplit.'
        return
    }

    foreach ($p in 18080..18090) {
        try { $px = New-Object SteamSplit.Proxy $p; $px.Start(); break } catch { $px = $null }
    }
    if (-not $px) { throw 'Khong mo duoc cong proxy nao (18080-18090 dang bi chiem).' }

    $ok = $false
    foreach ($m in 1, 2, 3) {
        $px.Mode = $m
        if ((Test-Steam $px.Port).Ok) { $ok = $true; break }
    }
    if (-not $ok) {
        Msg 'Khong vuot duoc. Nha mang co the chan theo IP; luc nay can VPN/WARP.' 'Warning'
        return
    }

    # Chi doi cai dat khi da chac chan chay duoc
    @{ Url = (Get-ItemProperty $Reg -ErrorAction SilentlyContinue).AutoConfigURL } | ConvertTo-Json | Set-Content $Backup
    Set-ItemProperty $Reg -Name AutoConfigURL -Value "http://127.0.0.1:$($px.Port)/proxy.pac?$(Get-Random)"
    [SteamSplit.Proxy]::RefreshSystemProxy()

    $status = "SteamSplit: dang hoat dong (kieu $($px.Mode))"
    $menu = New-Object Windows.Forms.ContextMenuStrip
    $menu.Items.Add('Test lai').add_Click({
        try {
            $tray.Text = 'SteamSplit: dang test lai...'
            $r = Test-Steam $px.Port
            $tray.Text = $status
            if ($r.Ok) { $tray.ShowBalloonTip(5000, 'Test lai: OK', $r.Text, 'Info') }
            else       { $tray.ShowBalloonTip(5000, 'Test lai: LOI', $r.Text, 'Warning') }
        } catch { }
    }) | Out-Null
    $menu.Items.Add('Tao loi tat ngoai Desktop').add_Click({
        try { New-Shortcut; $tray.ShowBalloonTip(4000, 'SteamSplit', 'Da tao loi tat SteamSplit ngoai Desktop.', 'Info') }
        catch { $tray.ShowBalloonTip(4000, 'SteamSplit', "Khong tao duoc loi tat: $($_.Exception.Message)", 'Warning') }
    }) | Out-Null
    $menu.Items.Add('Tat va khoi phuc').add_Click({ [Windows.Forms.Application]::Exit() }) | Out-Null
    $tray.ContextMenuStrip = $menu
    $tray.Text = $status
    $tray.ShowBalloonTip(6000, 'SteamSplit dang hoat dong',
        'Mo Steam nhu binh thuong. Dung xong: chuot phai icon nay > Tat va khoi phuc.', 'Info')

    [Windows.Forms.Application]::Run()
}
catch { Msg "Loi: $($_.Exception.Message)" 'Error' }
finally {
    $tray.Visible = $false
    $tray.Dispose()
    if ($px) { $px.Stop() }
    Restore-Proxy
    $mutex.ReleaseMutex()
}
