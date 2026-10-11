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

1. Nhấp đúp vào **`SteamSplit.cmd`**.
2. Đợi đến khi hiện chữ **DANG HOAT DONG**.
3. Mở Steam hoặc trình duyệt (Edge, Chrome) như bình thường.
4. **Giữ cửa sổ đó mở** trong suốt lúc dùng.
5. Dùng xong thì **nhấn Enter** trong cửa sổ để tắt. Cài đặt sẽ được trả lại như cũ.

Nếu web Steam bị thiếu hình, nhấn `Ctrl+F5`.

Muốn tạo lối tắt ngoài màn hình: chuột phải vào `SteamSplit.cmd`, chọn **Show more options**, rồi **Send to**, rồi **Desktop (create shortcut)**.

## Câu hỏi thường gặp

**Windows hiện cảnh báo "Windows protected your PC"?**
Lỗi này hay gặp với file tải bằng ZIP. Bấm **More info**, rồi **Run anyway**. Bạn có thể mở file bằng Notepad để tự đọc code trước khi chạy.

**Lỡ đóng cửa sổ bằng nút X?**
Steam có thể vẫn không vào được. Chỉ cần chạy lại `SteamSplit.cmd`: nó tự trả lại cài đặt cũ trước, rồi bật lại như bình thường.

**Chạy xong báo "Steam vao binh thuong"?**
Mạng của bạn không chặn Steam, không cần dùng công cụ này.

**Báo "Khong vuot duoc"?**
Nhà mạng đang chặn theo IP. Trường hợp này chỉ VPN hoặc WARP mới vượt được.

**Có giảm ping CS2 hay Valorant không?**
Không. Công cụ chỉ lo phần web Store và Community. Game có kết nối riêng, không đi qua công cụ này.

## Công cụ thay đổi gì trên máy

Chỉ đổi một khóa `AutoConfigURL` trong `HKCU\Software\Microsoft\Windows\CurrentVersion\Internet Settings` (cài đặt proxy tự động của Windows). Giá trị cũ được sao lưu vào `%LOCALAPPDATA%\SteamSplit-backup.json` và được trả lại khi tắt.

Công cụ chỉ kết nối tới các domain của Steam và `1.1.1.1` (dịch vụ DNS của Cloudflare). Nó không tự cập nhật và không gửi dữ liệu đi đâu khác.

Chi tiết kỹ thuật: [docs/SteamSplit-yeu-cau.md](docs/SteamSplit-yeu-cau.md) và [docs/test-report.md](docs/test-report.md).
