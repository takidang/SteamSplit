# SteamSplit: bao cao test

Ngay test: 2026-10-11. May: Windows 11 Home 10.0.26200, Windows PowerShell 5.1.26100, curl.exe co san, khong co quyen Admin.
Script test: tach khoi C# tu `SteamSplit.cmd`, tam doi `FindSni` va `Resolve` sang `public`, chay trong `powershell.exe` rieng. Tu 5.1 den 5.5 khong dong vao registry.

## Hien trang mang truoc khi test

| Kiem tra | Ket qua |
|---|---|
| `curl.exe https://store.steampowered.com/` | `000` (bi chan) |
| `curl.exe https://steamcommunity.com/` | `000` (bi chan) |
| DNS he thong cho `store.steampowered.com` | `127.0.0.1`, `::1` (nha mang lam gia DNS) |
| `curl.exe --resolve store.steampowered.com:443:104.119.106.101` | `200` |
| `AutoConfigURL` truoc khi test | trong (khong co gia tri) |
| File `%LOCALAPPDATA%\SteamSplit-backup.json` | khong co |

Ket luan: mang nay chi bi lam gia DNS, khong bi chan SNI. Chi can DoH la vao duoc; viec cat goi khong gay hai nhung o mang nay khong bat buoc.

## Ket qua

| Buoc | Noi dung | Ket qua |
|---|---|---|
| 5.1 | `Add-Type` khoi C# trong PowerShell 5.1 | DAT, khong co loi bien dich |
| 5.2 | ClientHello that tu `SslStream.AuthenticateAsClient("store.steampowered.com")` (449 byte), `FindSni` tra pos=131, nameLen=22, chuoi = `store.steampowered.com` | DAT |
| 5.3 | `GET /proxy.pac` tra PAC co `PROXY 127.0.0.1:18080; DIRECT` | DAT |
| 5.3 | `--proxy ... https://example.com`: proxy tra `403 Forbidden`, curl `000` | DAT |
| 5.3 | Kieu 1, 2, 3 qua proxy: store va community deu `200` | DAT (6/6) |
| 5.3 | Sau `Stop()` cong 18080 duoc nha | DAT |
| 5.4 | Bat goi bang pktmon | BO QUA: pktmon can quyen Admin, may test khong co |
| 5.5a | `Resolve("store.steampowered.com")` = `104.119.106.101`, trung `nslookup ... 1.1.1.1` | DAT (lan chay dau khac IP nhung cung dai Akamai 104.x, do CDN xoay IP) |
| 5.5b | DoH doi sang dia chi khong ton tai | Xem ghi chu loi 1 ben duoi. Sau khi sua: domain sach (`cdn.steamstatic.com`) tra `140.248.131.52` qua DNS he thong (DAT); domain bi lam gia thi bao loi ro rang thay vi tra `127.0.0.1` |
| 5.6.1-3 | Nguoi dung chay `SteamSplit.cmd`: truc tiep `[X]`, kieu 1 qua proxy `200`/`200`, bao "DANG HOAT DONG". Trong luc chay: `AutoConfigURL = http://127.0.0.1:18080/proxy.pac?514972162`, backup `{"Url": null}`, `example.com` di thang `200`. Nguoi dung mo store.steampowered.com bang trinh duyet: vao duoc | DAT |
| 5.6.4 | Nhan Enter: `AutoConfigURL` tro ve trong, file backup bi xoa, khong con cong 18080-18090 | DAT |
| 5.6.5 | Dong bang nut X: trinh duyet vao Steam bao `ERR_CONNECTION_REFUSED` | KHONG DAT tren mang nay, xem ghi chu 2 |
| 5.6.5 | Chay lai: dong dau la "Da tra lai cai dat proxy cu", sau do chay binh thuong | DAT |
| 5.7 | Ra soat bao mat | DAT, xem duoi |
| - | Script chi co ky tu ASCII | DAT (0 byte > 127) |

## Loi da sua

**Loi 1: fallback DNS tra IP gia cua nha mang.** Ban nhap khi DoH loi se lay IPv4 dau tien tu DNS he thong. Tren mang nay do la `127.0.0.1`, nen proxy se ket noi vao chinh may nguoi dung o cong 443 va cache IP sai do. Da sua trong `Resolve`: bo qua dia chi loopback va `0.0.0.0`. Neu khong con IP hop le thi nem loi "Khong phan giai duoc ...", ket noi do bi dong.

**Ghi chu 2: `; DIRECT` khong cuu duoc khi DNS bi lam gia.** Sau khi dong bang nut X, PAC chuyen sang `DIRECT`, nhung trinh duyet dung DNS nha mang va nhan `127.0.0.1`, nen bi tu choi ket noi. Trang thai nay giong het luc chua chay script (Steam van bi chan), may khong bi hong them, va chay lai script se don dep ngay. Muon sua thi phai doi DNS hoac `hosts`, ma muc 2 da cam, nen khong sua. Cach dung dung: tat bang Enter, khong bam X.

## 5.7 Ra soat bao mat

Tim `http|irm|iwr|iex|Invoke-|Start-Process|Set-ItemProperty|Remove-Item`:

- Dong 5 `iex`: chay phan PowerShell cua chinh file `.cmd` (doc tu `%~f0`), khong tai tu mang. Chap nhan.
- `https://1.1.1.1/dns-query`: DoH, nam trong danh sach cho phep.
- `http:` trong PAC, `HTTP/1.1` trong phan hoi proxy, `%{http_code}`: chuoi giao thuc, khong phai lenh goi mang.
- `curl.exe` chi goi `store.steampowered.com` va `steamcommunity.com`, co the qua `127.0.0.1`.
- `Set-ItemProperty` / `Remove-ItemProperty`: chi tren `AutoConfigURL` cua HKCU, sau khi da sao luu.
- `Remove-Item $Backup`: chi xoa file backup cua chinh script.
- Khong co `irm`, `iwr`, `Invoke-WebRequest`, `Invoke-RestMethod`, `Start-Process`.

## Tong ket

Tat ca cac buoc dat, tru 5.4 (bo qua vi can Admin) va 5.6.5 phan trinh duyet sau khi bam X (gioi han cua mang lam gia DNS, xem ghi chu 2).

Kiem tra cuoi sau khi thoat: `AutoConfigURL` trong (nhu ban dau), khong con file backup, khong con cong nao trong 18080-18090 dang lang nghe.
