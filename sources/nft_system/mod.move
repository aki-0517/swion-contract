module swion::nft_system {
    // NFT_SYSTEM One Time Witness for module initialization
    struct NFT_SYSTEM has drop {}

    use sui::tx_context;

    // OTW (One Time Witness) パターン: 初期化時に実行
    fun init(_otw: NFT_SYSTEM, _ctx: &mut tx_context::TxContext) {
        // モジュールパッケージの初期化完了。
        // 必要な初期化はサブモジュールのOTWによって自動的に行われる
    }
}