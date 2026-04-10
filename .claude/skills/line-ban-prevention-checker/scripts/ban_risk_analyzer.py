import sys

def analyze_file(filepath):
    try:
        with open(filepath, 'r', encoding='utf-8') as f:
            content = f.read()
    except Exception as e:
        print(f"ファイルの読み込みに失敗しました: {e}")
        return

    ng_words = ['儲かる', '儲ける', 'するだけ', '稼げる', '副業', '月収', '月商', '年収', '絶対', '直ぐに', '不労所得']
    
    print(f"=== BANリスク自動スキャン ({filepath}) ===")
    
    found = False
    lines = content.split('\n')
    for i, line in enumerate(lines, start=1):
        for word in ng_words:
            if word in line:
                print(f"行 {i}: ⚠️ 危険ワード「{word}」が含まれています。 -> {line.strip()}")
                found = True
                
    if not found:
        print("✅ 明白なNGワードは検出されませんでした。ただし文脈による審査もあるため、目視チェックも併用してください。")

if __name__ == '__main__':
    if len(sys.argv) < 2:
        print("使用法: python ban_risk_analyzer.py <ファイルパス>")
    else:
        analyze_file(sys.argv[1])
