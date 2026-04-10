"""
n8nワークフロー バリデーションスクリプト
JSONの構造・ノード接続・設定を自動検証する
"""
import sys
import json


def validate_workflow(file_path):
    """n8nワークフローJSONを検証する"""
    # --- JSONの読み込み ---
    try:
        with open(file_path, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except FileNotFoundError:
        print(f"Error: ファイルが見つかりません: {file_path}")
        return
    except json.JSONDecodeError as e:
        print(f"❌ JSON構文エラー: {e}")
        print("JSONの構文を修正してから再実行してください")
        return

    print("=== n8nワークフロー バリデーションレポート ===")
    print(f"ファイル: {file_path}")
    print()

    issues = []
    warnings = []

    # --- 基本構造チェック ---
    print("--- 基本構造チェック ---")

    # ワークフロー名
    wf_name = data.get('name', '(未設定)')
    print(f"  ワークフロー名: {wf_name}")
    if wf_name == '(未設定)' or wf_name == 'My workflow':
        warnings.append("ワークフロー名がデフォルトのままです。分かりやすい名前に変更してください")

    # ノード
    nodes = data.get('nodes', [])
    print(f"  ノード数: {len(nodes)}")
    if not nodes:
        issues.append("ノードが1つもありません")

    # 接続
    connections = data.get('connections', {})
    connection_count = sum(
        len(outputs)
        for node_conns in connections.values()
        for output_type in node_conns.values()
        for outputs in output_type
    ) if connections else 0
    print(f"  接続数: {connection_count}")
    print()

    # --- ノード分析 ---
    print("--- ノード一覧 ---")
    node_names = set()
    node_types = {}
    has_trigger = False
    has_error_handler = False

    for node in nodes:
        name = node.get('name', '(名前なし)')
        ntype = node.get('type', '(タイプ不明)')
        disabled = node.get('disabled', False)
        status = " [無効]" if disabled else ""

        node_names.add(name)
        node_types[name] = ntype
        print(f"  {'🔴' if disabled else '🟢'} {name} ({ntype}){status}")

        # トリガーノードの検出
        if 'trigger' in ntype.lower() or 'webhook' in ntype.lower() or 'schedule' in ntype.lower() or 'manual' in ntype.lower():
            has_trigger = True

        # エラーハンドリングの検出
        if 'error' in ntype.lower() or 'errorTrigger' in ntype.lower():
            has_error_handler = True

    print()

    if not has_trigger:
        warnings.append("トリガーノード（Manual Trigger / Webhook / Schedule等）が見つかりません。ワークフローを開始する方法がない可能性があります")

    if not has_error_handler and len(nodes) > 3:
        warnings.append("エラーハンドリングノードがありません。エラー発生時に通知を受け取れるよう追加を推奨します")

    # --- 接続整合性チェック ---
    print("--- 接続整合性チェック ---")
    connected_targets = set()
    orphan_check = set(n.get('name', '') for n in nodes)

    for source_name, source_conns in connections.items():
        if source_name not in node_names:
            issues.append(f"接続元「{source_name}」がノード一覧に存在しません（孤立した接続）")

        for output_type, output_groups in source_conns.items():
            for output_group in output_groups:
                for conn in output_group:
                    target = conn.get('node', '')
                    connected_targets.add(target)
                    if target and target not in node_names:
                        issues.append(f"接続先「{target}」がノード一覧に存在しません（接続切れ）")

    # 孤立ノード（どこからも接続されていないノード、トリガー以外）
    for node in nodes:
        name = node.get('name', '')
        ntype = node.get('type', '')
        is_trigger = 'trigger' in ntype.lower() or 'webhook' in ntype.lower() or 'schedule' in ntype.lower() or 'manual' in ntype.lower()
        if name not in connected_targets and not is_trigger and name in node_names:
            has_outgoing = name in connections
            if not has_outgoing:
                warnings.append(f"ノード「{name}」は入力も出力もない孤立ノードです")

    if not issues:
        print("  ✅ 接続の整合性に問題はありません")
    else:
        for issue in issues:
            print(f"  ❌ {issue}")
    print()

    # --- Credential チェック ---
    print("--- セキュリティチェック ---")
    security_issues = []
    raw_json = json.dumps(data)

    # パスワード・トークンの直接埋め込み検出
    sensitive_patterns = ['password', 'apiKey', 'token', 'secret', 'accessToken']
    for node in nodes:
        params = node.get('parameters', {})
        params_str = json.dumps(params)
        for pattern in sensitive_patterns:
            if pattern in params_str:
                # Credentialリファレンスではなく直接値の場合
                creds = node.get('credentials', {})
                if not creds:
                    security_issues.append(f"ノード「{node.get('name', '')}」にCredentialではなくパラメータとして機密情報({pattern})が含まれている可能性があります")

    # Webhook のセキュリティ
    for node in nodes:
        ntype = node.get('type', '')
        if 'webhook' in ntype.lower():
            params = node.get('parameters', {})
            auth = params.get('authentication', 'none')
            if auth == 'none':
                warnings.append(f"Webhookノード「{node.get('name', '')}」に認証が設定されていません")

    if security_issues:
        for si in security_issues:
            print(f"  ⚠ {si}")
    else:
        print("  ✅ 明らかなセキュリティリスクは検出されませんでした")
    print()

    # --- 総合結果 ---
    print("=== 総合判定 ===")
    if issues:
        print(f"  ❌ 致命的問題: {len(issues)} 件")
        for i, issue in enumerate(issues, 1):
            print(f"     {i}. {issue}")

    if warnings:
        print(f"  ⚠ 改善推奨: {len(warnings)} 件")
        for i, warning in enumerate(warnings, 1):
            print(f"     {i}. {warning}")

    if not issues and not warnings:
        print("  ✅ 問題は検出されませんでした。本番利用可能です。")
    elif not issues:
        print("  🟡 致命的な問題はありませんが、改善推奨事項があります。")
    else:
        print("  🔴 致命的な問題があります。修正してから使用してください。")


if __name__ == "__main__":
    if len(sys.argv) < 2:
        print("Usage: python n8n_validator.py <n8nワークフロー.json>")
    else:
        validate_workflow(sys.argv[1])
