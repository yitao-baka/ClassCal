"""阶段 1 的验收脚本：把教务系统页面上的课表网格与我们 ICS 导入的结果逐格比对。

用法：
    dart run tool/verify_ics_import.dart <课表.ics> --tsv > ours.tsv
    python -I tool/compare_with_scrape.py <xskb.html> ours.tsv

两个数据源完全独立 —— 一边是教务系统 HTML 里的格子，一边是我们自己的 ICS
解析 + 归并，因此这是一次真比对，不是自证。任一方向出现差异都会打印出来。

页面是 UTF-8（别被 gb18030 骗了：它几乎接受任何字节序列、不会报错，
先试它会把好数据悄悄解成乱码）。表格的行 = 大节（第一二节 … 第九十节），
列 = 星期；每格里的课程块用一行短横线分隔，块内信息在 `<font title="...">` 里。
"""
import io
import re
import sys

DASH = re.compile(r'-{5,}')

CN_DIGIT = {'一': 1, '二': 2, '三': 3, '四': 4, '五': 5,
            '六': 6, '七': 7, '八': 8, '九': 9}


def read_page(path):
    """Decode the page. Try UTF-8 strictly first: gb18030 accepts almost any
    byte sequence without raising, so trying it first would silently mangle a
    UTF-8 file into mojibake that still 'decodes fine'."""
    with open(path, 'rb') as f:
        raw = f.read()
    for enc in ('utf-8', 'gb18030'):
        try:
            return raw.decode(enc)
        except UnicodeDecodeError:
            continue
    return raw.decode('utf-8', errors='replace')


def strip_tags(s):
    s = re.sub(r'<br\s*/?>', '\n', s, flags=re.I)
    s = re.sub(r'<[^>]+>', '', s)
    s = s.replace('&nbsp;', ' ').replace('&amp;', '&')
    return s


def font_value(block, title):
    m = re.search(
        r'<font[^>]*title="%s"[^>]*>(.*?)</font>' % re.escape(title),
        block, re.S | re.I)
    if not m:
        return ''
    return strip_tags(m.group(1)).strip()


def parse_cell(td):
    """Return [(title, weeks, periods, room, teacher), ...] for one <td>."""
    # The visible block is class="kbcontent"; class="kbcontent1" is the
    # collapsed summary used by the mobile view and lacks period info.
    divs = re.findall(r'<div[^>]*class="kbcontent"[^>]*>(.*?)</div>', td, re.S | re.I)
    if not divs:
        return []
    # Prefer the longest - that is the one with teacher/period detail.
    body = max(divs, key=len)

    out = []
    for block in DASH.split(body):
        title = strip_tags(block).strip().split('\n')[0].strip()
        if not title:
            continue
        out.append({
            'title': title,
            'weeks': font_value(block, '周次(节次)'),
            'room': font_value(block, '教室'),
            'teacher': font_value(block, '教师'),
        })
    return out


def parse_weeks(s):
    """'15-16(周)[01-02节]' -> ('15-16', '1-2')"""
    m = re.match(r'\s*([\d,\-]+)\s*\(周\)\s*\[(\d+)-(\d+)节\]', s)
    if not m:
        m2 = re.match(r'\s*([\d,\-]+)\s*\(周\)', s)
        return (compress(m2.group(1)) if m2 else '', '')
    return (compress(m.group(1)), '%d-%d' % (int(m.group(2)), int(m.group(3))))


def compress(spec):
    """'5,6,7,8,9,11' -> '5-9,11'"""
    weeks = []
    for part in spec.split(','):
        part = part.strip()
        if '-' in part:
            a, b = part.split('-', 1)
            try:
                weeks.extend(range(int(a), int(b) + 1))
            except ValueError:
                pass
        elif part.isdigit():
            weeks.append(int(part))
    if not weeks:
        return spec
    weeks = sorted(set(weeks))
    parts = []
    start = prev = weeks[0]
    for w in weeks[1:]:
        if w == prev + 1:
            prev = w
            continue
        parts.append(str(start) if start == prev else '%d-%d' % (start, prev))
        start = prev = w
    parts.append(str(start) if start == prev else '%d-%d' % (start, prev))
    return ','.join(parts)


def main(html_path, tsv_path):
    html = read_page(html_path)
    tbl = re.search(r'<table[^>]*id="timetable".*?</table>', html, re.S | re.I)
    if not tbl:
        print('ERROR: #timetable not found')
        return 2
    rows = re.findall(r'<tr[^>]*>(.*?)</tr>', tbl.group(0), re.S | re.I)

    scraped = set()
    weekdays = 0
    for r in rows[1:]:  # rows[0] is the weekday header
        ths = re.findall(r'<th[^>]*>(.*?)</th>', r, re.S | re.I)
        tds = re.findall(r'<td[^>]*>(.*?)</td>', r, re.S | re.I)
        if not ths or not tds:
            continue
        label = strip_tags(ths[0]).strip()
        # Row headers read 第一二节 / 第三四节 / ... / 第九十节
        m = re.search(r'第([一二三四五六七八九十]+)节', label)
        if not m:
            continue
        start_period = CN_DIGIT.get(m.group(1)[0])
        if start_period is None:
            continue
        weekdays = max(weekdays, len(tds))
        for col, td in enumerate(tds, start=1):
            for c in parse_cell(td):
                wks, periods = parse_weeks(c['weeks'])
                if not periods:
                    continue
                sp, ep = periods.split('-')
                scraped.add((
                    str(col), str(start_period), str(start_period + 1),
                    c['title'], wks, c['room'], c['teacher'],
                ))

    ours = set()
    with io.open(tsv_path, encoding='utf-8') as f:
        for line in f:
            line = line.rstrip('\n')
            if not line.strip():
                continue
            ours.add(tuple(line.split('\t')))

    def norm(row):
        # room strings occasionally carry a trailing note; compare as-is first
        return row

    scraped_n = {norm(x) for x in scraped}
    ours_n = {norm(x) for x in ours}

    only_scrape = sorted(scraped_n - ours_n)
    only_ours = sorted(ours_n - scraped_n)

    print('教务系统抓取：%d 条课程规则' % len(scraped_n))
    print('我们导入的结果：%d 条课程规则' % len(ours_n))
    print()
    if not only_scrape and not only_ours:
        print('完全一致 —— 逐格匹配。')
        return 0
    if only_scrape:
        print('只在教务系统里有（%d）:' % len(only_scrape))
        for x in only_scrape:
            print('  ', ' | '.join(x))
    if only_ours:
        print('只在我们这边有（%d）:' % len(only_ours))
        for x in only_ours:
            print('  ', ' | '.join(x))
    return 1


if __name__ == '__main__':
    sys.exit(main(sys.argv[1], sys.argv[2]))
