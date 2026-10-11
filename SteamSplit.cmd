<# :
@echo off
title SteamSplit
set "SELF=%~f0"
powershell -NoProfile -ExecutionPolicy Bypass -Command "$s=[IO.File]::ReadAllText($env:SELF); iex $s.Substring($s.IndexOf('#'+'PS'+'#'))"
exit /b
#>
#PS#
# SteamSplit - mo Steam Store/Community khi bi chan, khong can admin, khong doi DNS/hosts.
# Cach lam: proxy noi bo (127.0.0.1) chi cho domain Steam; tu phan giai IP qua DoH 1.1.1.1;
# cat nho goi TLS ClientHello de lach bo loc SNI. Thoat la tra lai cai dat proxy cu.
# Khong co tu cap nhat, khong gui du lieu di dau ngoai Steam va 1.1.1.1.

$ErrorActionPreference = 'Stop'
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

$Reg    = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings'
$Backup = Join-Path $env:LOCALAPPDATA 'SteamSplit-backup.json'

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

function Test-Steam([int]$Port = 0) {
    foreach ($u in 'https://store.steampowered.com/', 'https://steamcommunity.com/') {
        $a = @('-s', '-o', 'NUL', '-w', '%{http_code}', '--max-time', '8')
        if ($Port) { $a += @('--proxy', "http://127.0.0.1:$Port") }
        $code = & curl.exe @a $u
        if (-not $code -or $code -eq '000') { Write-Host "  [X] $u" -ForegroundColor Red; return $false }
        Write-Host "  [OK] $u (HTTP $code)" -ForegroundColor Green
    }
    return $true
}

function Restore-Proxy {
    if (-not (Test-Path $Backup)) { return }
    $b = Get-Content $Backup -Raw | ConvertFrom-Json
    if ($b.Url) { Set-ItemProperty $Reg -Name AutoConfigURL -Value $b.Url }
    else        { Remove-ItemProperty $Reg -Name AutoConfigURL -ErrorAction SilentlyContinue }
    Remove-Item $Backup -Force
    [SteamSplit.Proxy]::RefreshSystemProxy()
    Write-Host '  Da tra lai cai dat proxy cu.' -ForegroundColor Cyan
}

$px = $null
try {
    Restore-Proxy   # lan truoc bi tat bang nut X thi don lai truoc

    Write-Host "`n  Kiem tra Steam truc tiep..." -ForegroundColor Cyan
    if (Test-Steam) {
        Write-Host "`n  Steam vao binh thuong, khong can lam gi." -ForegroundColor Green
        Read-Host '  Enter de thoat' | Out-Null
        return
    }

    foreach ($p in 18080..18090) {
        try { $px = New-Object SteamSplit.Proxy $p; $px.Start(); break } catch { $px = $null }
    }
    if (-not $px) { throw 'Khong mo duoc cong proxy nao (18080-18090 dang bi chiem).' }

    $ok = $false
    foreach ($m in 1, 2, 3) {
        Write-Host "`n  Thu kieu cat goi $m qua proxy 127.0.0.1:$($px.Port)..." -ForegroundColor Cyan
        $px.Mode = $m
        if (Test-Steam $px.Port) { $ok = $true; break }
    }
    if (-not $ok) {
        Write-Host "`n  Khong vuot duoc. Nha mang co the chan theo IP; luc nay can VPN/WARP." -ForegroundColor Red
        Read-Host '  Enter de thoat' | Out-Null
        return
    }

    # Chi doi cai dat khi da chac chan chay duoc
    @{ Url = (Get-ItemProperty $Reg -ErrorAction SilentlyContinue).AutoConfigURL } | ConvertTo-Json | Set-Content $Backup
    Set-ItemProperty $Reg -Name AutoConfigURL -Value "http://127.0.0.1:$($px.Port)/proxy.pac?$(Get-Random)"
    [SteamSplit.Proxy]::RefreshSystemProxy()

    Write-Host "`n  DANG HOAT DONG (kieu $($px.Mode)). Chi traffic Steam di qua proxy." -ForegroundColor Green
    Write-Host '  Giu cua so nay mo. Neu web Steam thieu hinh, bam Ctrl+F5.' -ForegroundColor Yellow
    while ($true) {
        $k = Read-Host "`n  [T] test lai | Enter = tat va khoi phuc"
        if ($k -notmatch '^[tT]') { break }
        Test-Steam $px.Port | Out-Null
    }
}
catch { Write-Host "  Loi: $($_.Exception.Message)" -ForegroundColor Red; Read-Host '  Enter de thoat' | Out-Null }
finally {
    if ($px) { $px.Stop() }
    Restore-Proxy
}
