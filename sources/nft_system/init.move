module swion::nft_system_init {
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::display;
    use sui::package;
    use std::string;

    use swion::nft_system_water_tank::{WaterTank};

    // 自身のモジュール名に対応するOne-Time Witness
    struct NFT_SYSTEM_INIT has drop {}

    /// Module initialization function - sets up the Display for WaterTank objects
    fun init(_witness: NFT_SYSTEM_INIT, ctx: &mut TxContext) {
        let publisher = package::claim<NFT_SYSTEM_INIT>(_witness, ctx);
        let display = display::new<WaterTank>(&publisher, ctx);

        display::add(&mut display, 
            string::utf8(b"name"), 
            string::utf8(b"Swion Water Tank")
        );
        display::add(&mut display, 
            string::utf8(b"description"), 
            string::utf8(b"A virtual water tank where you can place your aquatic objects")
        );
        display::add(&mut display, 
            string::utf8(b"link"), 
            string::utf8(b"https://swion.wal.app/0x{hexaddr}")
        );
        
        display::add(&mut display, 
            string::utf8(b"walrus site address"), 
            string::utf8(b"dynamic:{hexaddr}")
        );

        display::update_version(&mut display);
        
        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
    }

    // テスト用関数
    #[test_only]
    public fun init_for_testing(_ctx: &mut TxContext) {
        // テスト環境では初期化処理をスキップ。
        // 必要に応じてWaterTankのみを作成する
    }
} 