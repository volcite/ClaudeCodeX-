"""
コンテンツ品質チェッカースクリプト
文章の読みやすさ・表記揺れ・構成バランスを自動計測する
"""
import sys
import re


def check_quality(file_path):
    """文章品質をチェックする"""
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            content = f.read()
    except FileNotFoundError:
        print(f"Error: ファイルが見つかりません: {file_path}")
        return
    except UnicodeDecodeError:
        try:
            with open(file_path, 'r', encoding='shift_jis') as f:
                content = f.read()
        except Exception:
            print("Error: ファイルのエンコーディングを読み取れません")
            return

    lines = content.split('\n')
    # Markdown記法と空行を除いた純粋なテキスト行
    text_lines = [l for l in lines if l.strip() and not l.strip().startswith('#') and not l.strip().startswith('---')]
    total_chars = len(content.replace('\n', '').replace('\r', '').replace(' ', ''))

    print("=== コンテンツ品質チェックレポート ===")
    print(f"ファイル: {file_path}")
    print(f"総文字数: {total_chars:,} 文字")
    print(f"総行数: {len(lines)} 行 (テキスト行: {len(text_lines)})")
    print()

    issues = []

    # --- 1. 文長チェック ---
    print("--- 文長チェック ---")
    sentences = re.split(r'[。！？\n]', content)
    sentences = [s.strip() for s in sentences if s.strip() and len(s.strip()) > 5]
    if sentences:
        lengths = [len(s) for s in sentences]
        avg_len = sum(lengths) / len(lengths)
        max_len = max(lengths)
        long_count = sum(1 for l in lengths if l > 80)
        very_long_count = sum(1 for l in lengths if l > 120)
        print(f"  文数: {len(sentences)}")
        print(f"  平均文長: {avg_len:.0f}文字 [推奨: 40-60文字]")
        print(f"  最長文: {max_len}文字")
        print(f"  長文(80字超): {long_count}文")
        print(f"  超長文(120字超): {very_long_count}文")
        if very_long_count > 0:
            issues.append(f"120字を超える文が{very_long_count}文あります。分割を検討してください")
        if avg_len > 60:
            issues.append(f"平均文長が{avg_len:.0f}字です。40-60字が読みやすいです")
    print()

    # --- 2. 文末表現の重複チェック ---
    print("--- 文末表現チェック ---")
    endings = []
    for line in text_lines:
        line = line.strip().rstrip('*').rstrip()
        if line.endswith('です。') or line.endswith('です'):
            endings.append('です')
        elif line.endswith('ます。') or line.endswith('ます'):
            endings.append('ます')
        elif line.endswith('した。') or line.endswith('した'):
            endings.append('した')
        elif line.endswith('ません。') or line.endswith('ません'):
            endings.append('ません')
        else:
            endings.append(None)

    consecutive = 1
    max_consecutive = 1
    worst_ending = None
    for i in range(1, len(endings)):
        if endings[i] and endings[i] == endings[i-1]:
            consecutive += 1
            if consecutive > max_consecutive:
                max_consecutive = consecutive
                worst_ending = endings[i]
        else:
            consecutive = 1

    if max_consecutive >= 3:
        issues.append(f"「〜{worst_ending}」が{max_consecutive}回連続しています。リズムが単調になります")
        print(f"  ⚠ 「〜{worst_ending}」が{max_consecutive}回連続")
    else:
        print(f"  ✅ 文末の連続は{max_consecutive}回以内（良好）")
    print()

    # --- 3. 二重表現チェック ---
    print("--- 二重表現チェック ---")
    double_expressions = {
        'まず最初に': 'まず / 最初に',
        '一番最初': '最初 / 一番先',
        '一番最も': '最も / 一番',
        'あとで後から': 'あとで / 後から',
        '必ず必要': '必要 / 必ず要る',
        'すべて全部': 'すべて / 全部',
        '約およそ': '約 / およそ',
        'だいたいおよそ': 'だいたい / およそ',
        '各それぞれ': '各 / それぞれ',
        '返事を返す': '返事をする / 返す',
    }
    found_doubles = []
    for expr, fix in double_expressions.items():
        if expr in content:
            found_doubles.append(f"「{expr}」→ 「{fix}」")
    if found_doubles:
        for d in found_doubles:
            print(f"  ⚠ {d}")
            issues.append(f"二重表現: {d}")
    else:
        print("  ✅ 二重表現は検出されませんでした")
    print()

    # --- 4. 漢字率チェック ---
    print("--- 漢字率チェック ---")
    kanji = re.findall(r'[\u4e00-\u9fff]', content)
    kanji_ratio = len(kanji) / max(total_chars, 1) * 100
    print(f"  漢字率: {kanji_ratio:.1f}% [推奨: 20-30%]")
    if kanji_ratio > 35:
        issues.append(f"漢字率が{kanji_ratio:.1f}%と高めです。ひらがなに開くことを検討してください")
    elif kanji_ratio < 15:
        issues.append(f"漢字率が{kanji_ratio:.1f}%と低めです。幼稚な印象を与える可能性があります")
    print()

    # --- 5. 全角半角混在チェック ---
    print("--- 全角半角チェック ---")
    fullwidth_nums = re.findall(r'[０-９]', content)
    halfwidth_nums = re.findall(r'[0-9]', content)
    if fullwidth_nums and halfwidth_nums:
        print(f"  ⚠ 全角数字({len(fullwidth_nums)}個)と半角数字({len(halfwidth_nums)}個)が混在しています")
        issues.append("全角・半角数字が混在しています。統一してください")
    else:
        print("  ✅ 数字の全角半角は統一されています")

    fullwidth_alpha = re.findall(r'[Ａ-Ｚａ-ｚ]', content)
    if fullwidth_alpha:
        print(f"  ⚠ 全角英字が{len(fullwidth_alpha)}個あります。半角に統一推奨")
        issues.append("全角英字があります。半角に統一してください")
    print()

    # --- 6. 段落バランス ---
    print("--- 段落バランス ---")
    paragraphs = content.split('\n\n')
    paragraphs = [p.strip() for p in paragraphs if p.strip()]
    if paragraphs:
        para_lengths = [len(p.replace('\n', '')) for p in paragraphs]
        avg_para = sum(para_lengths) / len(para_lengths)
        long_paras = sum(1 for l in para_lengths if l > 300)
        print(f"  段落数: {len(paragraphs)}")
        print(f"  平均段落長: {avg_para:.0f}文字")
        print(f"  長い段落(300字超): {long_paras}個")
        if long_paras > 0:
            issues.append(f"300字を超える段落が{long_paras}個あります。読者の目が疲れます")
    print()

    # --- サマリー ---
    print("=== 検出された問題 ({} 件) ===".format(len(issues)))
    if issues:
        for i, issue in enumerate(issues, 1):
            print(f"  {i}. {issue}")
    else:
        print("  ✅ 問題は検出されませんでした")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python quality_checker.py <ファイルパス>")
    else:
        check_quality(sys.argv[1])
