#!/usr/bin/env python3
"""發佈前自我檢查：掃描資料夾裡的文字檔，找出可能洩漏個人或裝置資訊的內容。

用法：
  python3 tools/check_privacy.py [資料夾]                      # 預設掃描目前資料夾
  python3 tools/check_privacy.py . --names 我的電腦名稱 我的使用者名稱 我的帳號

--names：你自己的電腦名稱、使用者名稱、帳號、暱稱等。它們只用來比對，不會被寫進任何檔案。
有找到可疑內容時，結束碼是 1。「可能是版本號」的 IP 樣式請人工確認。
這支工具不能保證抓得到所有東西，貼出或發佈前仍請自己再看一次。
"""
import os, re, sys

RULES = {
    'IPv4 位址（可能是版本號，請人工確認）': r'\b(?:(?:25[0-5]|2[0-4]\d|1?\d?\d)\.){3}(?:25[0-5]|2[0-4]\d|1?\d?\d)\b',
    'IPv6 位址': r'\b(?:[0-9A-Fa-f]{1,4}:){4,7}[0-9A-Fa-f]{1,4}\b',
    'MAC 位址': r'\b[0-9A-Fa-f]{2}(?:[:-][0-9A-Fa-f]{2}){5}\b',
    '電子郵件': r'[\w.+-]+@[\w-]+\.[\w.-]+',
    '真實的機器 SID（S-1-5-21-數字）': r'S-1-5-21-\d{6,}-\d{6,}-\d{6,}',
    '電腦名稱樣式（DESKTOP-／LAPTOP-）': r'\b(?:DESKTOP|LAPTOP)-[A-Z0-9]{5,}\b',
    '網址裡帶 token、code、key': r'https?://[^\s)>\]]*(?:code|token|key|secret|session|sig)=[^\s)>\]]+',
    '路徑裡有使用者名稱（C:\\Users\\某人）': r'C:\\Users\\(?!<USER>|Public\b|Default\b|\*|<|%)[^\\\s`"\']+',
    '序號、機器識別類關鍵字': r'(?i)\bserial\s*number\b|\bMachineGuid\b|\bHWID\b|\bBIOS\s*serial\b|\bDeviceID\s*[:=]',
}
TEXT_EXT = ('.md', '.txt', '.ps1', '.py', '.json', '.yml', '.yaml', '.csv', '.reg', '.cmd', '.bat', '.html')

def main():
    args = sys.argv[1:]
    names = []
    if '--names' in args:
        i = args.index('--names'); names = args[i + 1:]; args = args[:i]
    root = args[0] if args else '.'
    hits = 0
    for dp, dn, fn in os.walk(root):
        dn[:] = [d for d in dn if d not in ('.git', 'node_modules')]
        for f in fn:
            if not f.lower().endswith(TEXT_EXT): continue
            p = os.path.join(dp, f)
            try: t = open(p, encoding='utf-8-sig', errors='replace').read()
            except OSError: continue
            for label, pat in RULES.items():
                for m in re.finditer(pat, t):
                    ln = t[:m.start()].count('\n') + 1
                    ctx = t[max(0, m.start() - 20):m.end() + 20].replace('\n', ' ')
                    print(f'[{label}] {p}:{ln}  …{ctx}…'); hits += 1
            for n in names:
                if not n: continue
                for m in re.finditer(re.escape(n), t, re.I):
                    ln = t[:m.start()].count('\n') + 1
                    print(f'[你提供的名稱「{n[:2]}…」] {p}:{ln}'); hits += 1   # 不印出完整名稱，避免再洩漏
    print('\n' + (f'共 {hits} 筆可疑內容。' if hits else '沒有發現可疑內容。'))
    return 1 if hits else 0

if __name__ == '__main__':
    sys.exit(main())
