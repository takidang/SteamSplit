# SteamSplit

Mở lại Steam Store và Steam Community khi nhà mạng chặn, **không cần bật VPN hay WARP** (nên không làm tăng ping game).

- Một file duy nhất, không cài đặt gì, không cần quyền Admin.
- Không đổi DNS, không sửa file `hosts`.
- Chỉ chuyển trang web Steam qua proxy nội bộ (`127.0.0.1`). Các trang khác vẫn đi thẳng như bình thường.

## Tải về

Có git:

```
git clone https://github.com/takidang/SteamSplit.git
```

Không có git: bấm nút **Code**, chọn **Download ZIP**, rồi giải nén ra.

## Cách dùng

1. Nhấp đúp vào **`SteamSplit.cmd`**. Một cửa sổ đen lóe lên rồi tự tắt, như vậy là bình thường.
2. Ở góc phải thanh taskbar xuất hiện icon TAKIRYU (ô vuông chữ neon xanh tím). Đợi vài giây đến khi có thông báo **SteamSplit dang hoat dong**.
3. Mở Steam hoặc trình duyệt (Edge, Chrome) như bình thường.
4. Dùng xong thì **chuột phải vào icon TAKIRYU**, chọn **Tat va khoi phuc**. Cài đặt sẽ được trả lại như cũ.

Nếu không thấy icon, bấm vào mũi tên `^` ở góc phải taskbar, icon có thể đang nằm trong đó.

Nếu web Steam bị thiếu hình, nhấn `Ctrl+F5`.

Lần chạy đầu, app hỏi có muốn tạo lối tắt **SteamSplit** ngoài Desktop không. Chọn **Yes** thì lần sau chỉ cần nhấp đúp lối tắt đó. Lỡ xóa lối tắt, hoặc lúc đầu đã chọn No: chuột phải icon TAKIRYU ở khay, chọn **Tao loi tat ngoai Desktop**. Nếu sau này dời thư mục đi chỗ khác, chạy `SteamSplit.cmd` ở chỗ mới một lần là lối tắt tự sửa lại.

## Câu hỏi thường gặp

**Windows hiện cảnh báo "Windows protected your PC"?**
Lỗi này hay gặp với file tải bằng ZIP. Bấm **More info**, rồi **Run anyway**. Bạn có thể mở file bằng Notepad để tự đọc code trước khi chạy.

**Tắt máy hoặc khởi động lại khi app đang chạy?**
Không sao. Lần sau chạy lại `SteamSplit.cmd`, nó tự trả lại cài đặt cũ trước rồi mới bật lên.

**Nhấp đúp hai lần?**
App chỉ chạy một bản. Lần nhấp thứ hai sẽ báo app đang chạy rồi.

**Chạy xong báo "Steam vao binh thuong"?**
Mạng của bạn không chặn Steam, không cần dùng công cụ này.

**Báo "Khong vuot duoc"?**
Nhà mạng đang chặn theo IP. Trường hợp này chỉ VPN hoặc WARP mới vượt được.

**Có giảm ping CS2 hay Valorant không?**
Không. Công cụ chỉ lo phần web Store và Community. Game có kết nối riêng, không đi qua công cụ này.

## Công cụ thay đổi gì trên máy

Chỉ đổi một khóa `AutoConfigURL` trong `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` (cài đặt proxy tự động của Windows). Giá trị cũ được sao lưu vào `%LOCALAPPDATA%\SteamSplit-backup.json` và được trả lại khi tắt.

Nếu bạn đồng ý, app tạo thêm lối tắt `SteamSplit.lnk` ngoài Desktop. Nếu bạn từ chối, app ghi một file trống `%LOCALAPPDATA%\SteamSplit-noshortcut` để nhớ không hỏi lại. Muốn được hỏi lại thì xóa file này.

Công cụ chỉ kết nối tới các domain của Steam và `1.1.1.1` (dịch vụ DNS của Cloudflare). Nó không tự cập nhật và không gửi dữ liệu đi đâu khác.

Chi tiết kỹ thuật: [docs/SteamSplit-yeu-cau.md](docs/SteamSplit-yeu-cau.md) và [docs/test-report.md](docs/test-report.md).
