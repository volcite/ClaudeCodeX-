"""
記事構成分析スクリプト
Markdownファイルの見出し構造・文字数・比率を自動分析する
"""
import sys
import re


def analyze_structure(file_path):
    """Markdownファイルの構成を分析する"""
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
    total_chars = len(content.replace('\n', '').replace('\r', '').replace(' ', ''))

    print(f"=== 記事構成分析レポート ===")
    print(f"ファイル: {file_path}")
    print(f"総文字数: {total_chars:,} 文字")
    print(f"総行数: {len(lines)} 行")
    print()

    # 見出し抽出
    headings = []
    for i, line in enumerate(lines):
        match = re.match(r'^(#{1,6})\s+(.+)', line.strip())
        if match:
            level = len(match.group(1))
            title = match.group(2).strip()
            headings.append({
                'line': i + 1,
                'level': level,
                'title': title
            })

    print(f"--- 見出し構造 ({len(headings)} 件) ---")
    for h in headings:
        indent = "  " * (h['level'] - 1)
        print(f"  {indent}{'#' * h['level']} {h['title']} (L{h['line']})")

    # セクション別文字数
    print()
    print("--- セクション別文字数 ---")
    sections = []
    for idx, h in enumerate(headings):
        start_line = h['line']
        end_line = headings[idx + 1]['line'] - 1 if idx + 1 < len(headings) else len(lines)
        section_text = '\n'.join(lines[start_line:end_line])
        char_count = len(section_text.replace('\n', '').replace('\r', '').replace(' ', ''))
        ratio = (char_count / total_chars * 100) if total_chars > 0 else 0
        sections.append({
            'title': h['title'],
            'level': h['level'],
            'chars': char_count,
            'ratio': ratio
        })
        bar = "█" * int(ratio / 2)
        print(f"  [{ratio:5.1f}%] {bar} {h['title']} ({char_count:,}字)")

    # 導入・本文・まとめの比率推定
    print()
    print("--- 構成バランス分析 ---")
    if len(sections) >= 3:
        intro_chars = sections[0]['chars'] if sections else 0
        conclusion_chars = sections[-1]['chars'] if sections else 0
        body_chars = total_chars - intro_chars - conclusion_chars
        print(f"  導入部: {intro_chars:,}字 ({intro_chars/total_chars*100:.1f}%) [推奨: 10-20%]")
        print(f"  本文:   {body_chars:,}字 ({body_chars/total_chars*100:.1f}%) [推奨: 60-75%]")
        print(f"  まとめ: {conclusion_chars:,}字 ({conclusion_chars/total_chars*100:.1f}%) [推奨: 10-15%]")
    else:
        print("  ※ セクションが少なすぎるため、バランス分析をスキップ")

    # 警告チェック
    print()
    print("--- 自動検出された注意点 ---")
    warnings = []

    # 長すぎるセクション
    for s in sections:
        if s['chars'] > 2000:
            warnings.append(f"[長文注意] 「{s['title']}」が{s['chars']:,}字あります。読者の離脱を防ぐため分割を検討してください")

    # 見出しレベルの飛び
    for i in range(1, len(headings)):
        if headings[i]['level'] > headings[i-1]['level'] + 1:
            warnings.append(f"[階層飛び] L{headings[i]['line']}: h{headings[i-1]['level']}→h{headings[i]['level']} の飛びがあります")

    # 導入が短すぎる
    if sections and sections[0]['ratio'] < 5:
        warnings.append("[導入不足] 導入部が全体の5%未満です。読者を引き込むフック文を追加してください")

    # CTAの有無
    cta_patterns = r'(クリック|購入|申し込|登録|ダウンロード|今すぐ|こちら|詳しく|お問い合わせ)'
    if not re.search(cta_patterns, content):
        warnings.append("[CTA不足] 行動喚起（CTA）が見当たりません")

    if warnings:
        for w in warnings:
            print(f"  ⚠ {w}")
    else:
        print("  ✅ 自動検出による注意点はありません")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python structure_analyzer.py <ファイルパス>")
    else:
        analyze_structure(sys.argv[1])
