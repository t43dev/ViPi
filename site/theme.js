// Đặt giao diện sáng/tối trước khi vẽ trang để không bị nháy; không lưu gì thì theo macOS.
try {
  var saved = localStorage.getItem('vipi-theme');
  if (saved === 'light' || saved === 'dark') document.documentElement.dataset.theme = saved;
} catch (e) {}
