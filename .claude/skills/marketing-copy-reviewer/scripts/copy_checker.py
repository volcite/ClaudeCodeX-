"""
セールスコピー分析スクリプト
パワーワード・CTA・心理テクニック表現・読みやすさを自動計測する
"""
import sys
import re


def analyze_copy(file_path):
    """セールスコピーを分析する"""
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

    print("=== セールスコピー分析レポート ===")
    print(f"ファイル: {file_path}")
    print(f"総文字数: {total_chars:,} 文字")
    print()

    # --- パワーワード分析 ---
    power_words = {
        '緊急性': ['今すぐ', '今だけ', '期間限定', '残りわずか', '急いで', '本日限り', '締切', 'ラスト', '最後の'],
        '希少性': ['限定', '特別', '先着', '残り', '人数制限', '二度とない', '一度きり'],
        '無料・お得': ['無料', 'タダ', '0円', '半額', '割引', '特典', 'ボーナス', 'プレゼント', 'お得'],
        '保証・安心': ['保証', '返金', 'リスクなし', '安心', 'サポート', '安全'],
        '権威・実績': ['実績', '証明', 'プロ', '専門家', '第一人者', '○○万人', '累計'],
        '感情喚起': ['衝撃', '驚き', '秘密', '真実', '暴露', '禁断', '革命', '人生が変わる', '最強'],
        '簡単さ': ['簡単', 'たった', 'だけ', 'コピペ', 'ワンクリック', '数分で', '誰でも'],
    }

    print("--- パワーワード使用状況 ---")
    total_power_words = 0
    for category, words in power_words.items():
        found = []
        for word in words:
            count = content.count(word)
            if count > 0:
                found.append(f"{word}({count})")
                total_power_words += count
        status = "✅" if found else "❌"
        found_str = ", ".join(found) if found else "なし"
        print(f"  {status} {category}: {found_str}")
    print(f"  合計: {total_power_words} 個 (密度: {total_power_words/max(total_chars,1)*1000:.1f}/1000文字)")
    print()

    # --- CTA分析 ---
    cta_patterns = [
        r'(クリック|タップ).*(して|する)',
        r'(購入|申し込|申込|登録|ダウンロード)',
        r'今すぐ',
        r'(こちら|ここ)から',
        r'(お問い合わせ|相談|予約)',
        r'(手に入れ|受け取)',
        r'(始め|スタート)',
    ]
    print("--- CTA（行動喚起）分析 ---")
    cta_count = 0
    for i, line in enumerate(lines):
        for pattern in cta_patterns:
            if re.search(pattern, line):
                cta_count += 1
                preview = line.strip()[:60]
                print(f"  📌 L{i+1}: {preview}...")
                break
    print(f"  CTA数: {cta_count} 個")
    if cta_count == 0:
        print("  ⚠ CTAが見つかりません。行動喚起を追加してください")
    elif cta_count < 3:
        print("  ⚠ CTAが少なめです。スクロール位置に応じて複数配置を推奨")
    print()

    # --- 読みやすさ分析 ---
    print("--- 読みやすさ分析 ---")
    sentences = re.split(r'[。！？\n]', content)
    sentences = [s.strip() for s in sentences if s.strip()]
    if sentences:
        avg_length = sum(len(s) for s in sentences) / len(sentences)
        long_sentences = [s for s in sentences if len(s) > 80]
        print(f"  平均文長: {avg_length:.0f}文字/文 [推奨: 40-60文字]")
        print(f"  長文(80字超): {len(long_sentences)}文")

    # 漢字率
    kanji = re.findall(r'[\u4e00-\u9fff]', content)
    kanji_ratio = len(kanji) / max(total_chars, 1) * 100
    print(f"  漢字率: {kanji_ratio:.1f}% [推奨: 20-30%]")

    # 同じ文末の連続
    endings = []
    for line in lines:
        line = line.strip()
        if line.endswith('です。'):
            endings.append('です')
        elif line.endswith('ます。'):
            endings.append('ます')
        elif line.endswith('した。'):
            endings.append('した')
        else:
            endings.append(None)

    consecutive = 0
    max_consecutive = 0
    for e in endings:
        if e and endings and consecutive > 0 and e == endings[endings.index(e)-1] if consecutive > 0 else False:
            consecutive += 1
            max_consecutive = max(max_consecutive, consecutive)
        else:
            consecutive = 1

    print()

    # --- 心理テクニック使用チェック ---
    print("--- 心理テクニック簡易チェック ---")
    techniques = {
        '社会的証明': r'(お客様の声|○○人|レビュー|評価|体験談|実績)',
        '損失回避': r'(失う|損|後悔|取り返し|手遅れ|逃す|もったいない)',
        '希少性': r'(限定|残り|先着|今だけ|二度と|最後)',
        '権威性': r'(専門|プロ|年|実績|累計|認定)',
        '返報性': r'(無料|プレゼント|特典|ボーナス|お渡し)',
        'アンカリング': r'(定価|通常|本来|元々|円のところ)',
        'ストーリー': r'(ある日|かつて|当時|あの頃|きっかけ|体験)',
        '未来想起': r'(想像|イメージ|3ヶ月後|1年後|未来|手に入れたら)',
    }
    for name, pattern in techniques.items():
        found = re.findall(pattern, content)
        status = "✅" if found else "❌"
        examples = list(set(found))[:3]
        print(f"  {status} {name}: {', '.join(examples) if examples else '未使用'}")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python copy_checker.py <ファイルパス>")
    else:
        analyze_copy(sys.argv[1])
