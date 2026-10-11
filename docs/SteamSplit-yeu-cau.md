# SteamSplit: yêu cầu dựng và test

Tài liệu này để giao cho Claude (Claude Code / Claude desktop có quyền chạy lệnh trên máy Windows) dựng và test công cụ. Đọc hết trước khi làm.

## 1. Mục tiêu

Ở Việt Nam, Steam Store và Steam Community đôi lúc không vào được. Nguyên nhân thường là nhà mạng làm giả DNS hoặc chặn theo SNI. Công cụ cần mở lại được các trang này mà không phải bật WARP/VPN, vì VPN làm ping game cao.

Ý tưởng lấy từ repo `vuviett47/SteamAccessFix`, nhưng làm lại theo hướng an toàn hơn và đơn giản hơn.

## 2. Nguyên tắc bắt buộc

- **KISS / YAGNI:** một file `SteamSplit.cmd` duy nhất (batch gọi PowerShell, C# nhúng qua `Add-Type`). Không cài thư viện, không driver, không dịch vụ nền.
- **Không cần quyền Admin.**
- **Không** đổi DNS của card mạng, **không** sửa file `hosts`.
- **Không** tự cập nhật, không tải code từ mạng về chạy.
- Chỉ gọi mạng tới: domain Steam và `https://1.1.1.1/dns-query` (DoH). Không gửi dữ liệu người dùng đi đâu khác.
- Proxy chỉ lắng nghe trên `127.0.0.1` và chỉ nhận kết nối tới domain Steam. Domain khác trả `403`.
- Thay đổi duy nhất trên máy là khóa `AutoConfigURL` trong `HKCU:\Software\Microsoft\Windows\CurrentVersion\Internet Settings`. Khóa này phải được sao lưu trước khi đổi và trả lại khi thoát.
- Chỉ đặt `AutoConfigURL` **sau khi** đã test qua proxy thành công. Nếu thất bại thì máy giữ nguyên.
- Script chỉ dùng ký tự ASCII (tiếng Việt không dấu) để tránh lỗi mã hóa của cmd / PowerShell 5.1.
- C# phải biên dịch được bằng trình biên dịch có sẵn của Windows PowerShell 5.1 (C# 5). Không dùng `$"..."`, `out var`, `=>`, `?.`.

## 3. Cách hoạt động

1. **Kiểm tra trực tiếp:** dùng `curl.exe` gọi `https://store.steampowered.com/` và `https://steamcommunity.com/`. Nếu cả hai có mã HTTP khác `000` thì báo "vào bình thường" và thoát mà không thay đổi gì.
2. **Bật proxy nội bộ:** mở cổng đầu tiên còn trống trong khoảng 18080 đến 18090 trên `127.0.0.1`. Proxy làm các việc sau:
   - `GET /proxy.pac` trả file PAC. File này đưa domain Steam qua `PROXY 127.0.0.1:<port>; DIRECT` (có `DIRECT` để tự đi thẳng nếu proxy chết); URL `http:` và mọi domain khác đi `DIRECT`.
   - `CONNECT host:port`: kiểm tra host thuộc danh sách Steam, phân giải IP qua DoH 1.1.1.1 (lỗi thì dùng DNS hệ thống, có cache), kết nối tới server, trả `200 Connection Established`.
   - Đọc trọn bản ghi TLS ClientHello đầu tiên, tìm vị trí tên miền trong extension SNI, rồi gửi gói thành nhiều mảnh (`Flush` và nghỉ khoảng 20 ms giữa các mảnh). Phần còn lại chuyển tiếp hai chiều bình thường.
   - Các kiểu cắt: `1` cắt giữa tên SNI, `2` cắt sau byte đầu tiên, `3` cắt cả hai chỗ.
3. **Thử lần lượt kiểu 1, 2, 3:** test bằng `curl.exe --proxy http://127.0.0.1:<port>`. Dừng ở kiểu đầu tiên chạy được.
4. **Kích hoạt:** sao lưu `AutoConfigURL` cũ vào `%LOCALAPPDATA%\SteamSplit-backup.json`, đặt `AutoConfigURL = http://127.0.0.1:<port>/proxy.pac?<số ngẫu nhiên>`, rồi gọi `InternetSetOption` (39 và 37) để Windows nhận cài đặt mới.
5. **Vòng điều khiển:** gõ `T` để test lại; nhấn Enter để tắt proxy, khôi phục cài đặt và thoát. Dùng `try/finally` để Ctrl+C cũng khôi phục được.
6. **Dọn phiên cũ:** đầu chương trình, nếu file backup còn tồn tại (lần trước bị tắt bằng nút X) thì khôi phục trước khi làm gì khác.

Danh sách domain Steam: `steampowered.com, steamcommunity.com, steamstatic.com, steam-chat.com, steamusercontent.com, steamgames.com, steamcontent.com`. Khớp đúng tên hoặc tên con (`*.domain`).

## 4. Bản nháp có sẵn

File `SteamSplit.cmd` đi kèm đã cài đặt đúng các ý trên nhưng **chưa từng chạy trên Windows**. Hãy dùng nó làm điểm xuất phát, sửa lỗi nếu có. Không viết lại từ đầu nếu không cần.

## 5. Kế hoạch test

Làm theo thứ tự. Ghi kết quả từng bước vào `test-report.md` (lệnh đã chạy, kết quả, đạt hay không).

**Quy tắc an toàn khi test:**
- Đọc lại toàn bộ script trước khi chạy.
- Từ bước 5.1 đến 5.5 chỉ tách phần C# ra test riêng; **không** đụng registry.
- Trước bước 5.6, ghi lại giá trị `AutoConfigURL` hiện tại và hỏi người dùng trước khi chạy.

### 5.1 Biên dịch
Trong **Windows PowerShell 5.1** (`powershell.exe`, không phải `pwsh`), tách khối C# ra và chạy `Add-Type`. Đạt khi không có lỗi biên dịch.

### 5.2 Phân tích SNI
Tạo một ClientHello thật, ví dụ dùng `SslStream.AuthenticateAsClient("store.steampowered.com")` kết nối tới một `TcpListener` cục bộ, rồi bắt các byte đầu tiên mà listener nhận được. Gọi `FindSni` (tạm đổi sang `public` hoặc dùng reflection). Đạt khi chuỗi ASCII tại vị trí trả về, với độ dài `nameLen`, đúng bằng `store.steampowered.com`.

### 5.3 Proxy cơ bản
Khởi tạo `SteamSplit.Proxy` trên một cổng trống, rồi kiểm tra:
- `curl.exe -s http://127.0.0.1:<port>/proxy.pac`: trả về PAC có đúng cổng và có `; DIRECT`.
- `curl.exe -s -o NUL -w "%{http_code}" --proxy http://127.0.0.1:<port> https://example.com`: thất bại (proxy trả 403).
- Với từng kiểu 1, 2, 3: `curl.exe -s -o NUL -w "%{http_code}" --proxy http://127.0.0.1:<port> https://store.steampowered.com/` trả mã khác `000`.

### 5.4 Kiểm tra mảnh gói (nếu có Wireshark hoặc pktmon)
Bắt gói khi test kiểu 1. Đạt khi ClientHello đi thành ít nhất hai segment TCP và tên SNI bị tách giữa các segment. Không có công cụ bắt gói thì bỏ qua và ghi chú lại.

### 5.5 DoH và dự phòng
- Gọi `Resolve("store.steampowered.com")` và so với `nslookup store.steampowered.com 1.1.1.1`.
- Mô phỏng DoH lỗi, ví dụ tạm đổi URL sang một địa chỉ không tồn tại. Đạt khi hàm vẫn trả IP qua DNS hệ thống.

### 5.6 Chạy toàn bộ (cần người dùng đồng ý)
1. Chạy `SteamSplit.cmd`.
2. Nếu mạng đang vào Steam bình thường: xác nhận script báo "vao binh thuong", `AutoConfigURL` không đổi, không có file backup.
3. Nếu mạng đang bị chặn: xác nhận `AutoConfigURL` trỏ tới `127.0.0.1`, mở `https://store.steampowered.com` bằng Edge hoặc Chrome thì vào được, các trang không phải Steam vẫn đi thẳng.
4. Nhấn Enter. Xác nhận `AutoConfigURL` trở về giá trị cũ và file backup đã bị xóa.
5. Chạy lại, rồi đóng cửa sổ bằng nút X. Mở trình duyệt vào Steam: vẫn vào được (nhờ `; DIRECT`). Chạy lại script: nó báo đã khôi phục cài đặt cũ.

### 5.7 Rà soát bảo mật cuối
Tìm trong script mọi `http`, `irm`, `iwr`, `iex`, `Invoke-`, `Start-Process`, `Set-ItemProperty`, `Remove-Item`. Xác nhận mỗi chỗ đều nằm trong danh sách cho phép ở mục 2.

## 6. Tiêu chí hoàn thành

- Toàn bộ các bước trong mục 5 đạt, hoặc có ghi chú rõ vì sao bỏ qua.
- Sau khi thoát, máy không còn thay đổi nào: `AutoConfigURL` như cũ, không còn file backup, không còn tiến trình nào giữ cổng 18080 đến 18090.
- Giao lại `SteamSplit.cmd` (bản đã sửa, nếu có sửa) và `test-report.md`.

## 7. Ngoài phạm vi

- Ping và kết nối trong game (CS2 và Valorant dùng UDP riêng, không đi qua proxy này).
- Nhà mạng chặn theo IP. Trường hợp này cách làm này không vượt được, script chỉ cần báo rõ cho người dùng.
- Giao diện đồ họa hoặc biểu tượng ở khay hệ thống: chỉ làm khi được yêu cầu.
