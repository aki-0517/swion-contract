module suiden::nft_system {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url;
    use std::string;
    use std::vector;

    /////////////////////////////////
    // Structures
    /////////////////////////////////

    /// ウォータータンクSBTの構造体
    struct WaterTank has key, store {
        id: UID,
        owner: address,
        // タンクに添付されたNFT ObjectのID一覧
        child_objects: vector<ID>,
        // 背景画像URI（walrus保存用）
        background_image: url::Url,
        // 現在のレベル
        level: u64
    }

    /// 個々のNFT Objectを表す構造体
    /// UID を含むため drop 能力は付与しません
    struct NFTObject has key, store {
        id: UID,
        owner: address,
        image: url::Url,
        name: string::String,
        // mint_flag はシリアライズされた情報をバイトベクターで保持
        mint_flag: vector<u8>,
        // NFTObject の配置情報: x軸と y軸
        position_x: u64,
        position_y: u64
    }

    /// 複数のNFT Objectを連携した SynObject の構造体
    struct SynObject has key, store {
        id: UID,
        // 追加: SynObject の所有者
        owner: address,
        // 連携する NFTObject の ID 一覧
        attached_objects: vector<ID>,
        image: url::Url,
        // 各 NFT Object の mint_flag 情報（バイトベクターのリスト）
        mint_flags: vector<vector<u8>>,
        // 公開状態
        is_public: bool
    }

    /////////////////////////////////
    // Events
    /////////////////////////////////

    struct MintWaterTankEvent has copy, drop {
        tank_id: ID,
        owner: address
    }

    struct UpdateObjectPositionEvent has copy, drop {
        nft_id: ID,
        new_x: u64,
        new_y: u64
    }

    struct AttachObjectEvent has copy, drop {
        tank_id: ID,
        object_id: ID
    }

    struct MintNFTObjectEvent has copy, drop {
        nft_id: ID,
        owner: address,
        name: string::String
    }

    struct MintSynObjectEvent has copy, drop {
        syn_id: ID,
        creator: address
    }

    /////////////////////////////////
    // Entry Functions
    /////////////////////////////////

    /// 新規ウォータータンクSBTの初期化  
    /// - `background_image`: 背景画像のURIをバイトベクター（例："https://example.com/bg.png"）として受け取る  
    /// - `level`: 初期レベル
    public entry fun initialize_tank(
        owner: address,
        background_image: vector<u8>,
        level: u64,
        ctx: &mut TxContext
    ) {
        let bg_url = url::new_unsafe_from_bytes(background_image);
        let tank = WaterTank {
            id: sui::object::new(ctx),
            owner: owner,
            child_objects: vector::empty<ID>(),
            background_image: bg_url,
            level: level
        };
        event::emit(MintWaterTankEvent {
            tank_id: sui::object::uid_to_inner(&tank.id),
            owner: owner
        });
        transfer::public_transfer(tank, owner);
    }

    /// ウォータータンク内に添付された NFTObject の位置（x, y）を更新する
    public entry fun update_object_position(
        tank: &WaterTank,
        nft: &mut NFTObject,
        new_x: u64,
        new_y: u64,
        ctx: &mut TxContext
    ) {
        let sender = sui::tx_context::sender(ctx);
        // タンクのオーナーのみが更新可能
        assert!(sender == tank.owner, 1);
        nft.position_x = new_x;
        nft.position_y = new_y;
        event::emit(UpdateObjectPositionEvent {
            nft_id: sui::object::uid_to_inner(&nft.id),
            new_x: new_x,
            new_y: new_y
        });
    }

    /// ウォータータンクに NFTObject を添付する  
    /// NFTObject は mutable reference で受け取ることで、値の move を避けます
    public entry fun attach_object(
        tank: &mut WaterTank,
        nft: &mut NFTObject,
        ctx: &mut TxContext
    ) {
        let sender = sui::tx_context::sender(ctx);
        // タンクのオーナーであることをチェック
        assert!(sender == tank.owner, 2);
        let nft_id = sui::object::uid_to_inner(&nft.id);
        vector::push_back(&mut tank.child_objects, nft_id);
        event::emit(AttachObjectEvent {
            tank_id: sui::object::uid_to_inner(&tank.id),
            object_id: nft_id
        });
    }

    /// 個々の NFTObject の mint  
    /// - `name`: NFT の名称（バイトベクター）  
    /// - `image`: 画像 URI（バイトベクター）  
    /// - `mint_flag`: mint 条件等の情報（シリアライズ済みバイトベクター）
    public entry fun mint_nft_object(
        name: vector<u8>,
        image: vector<u8>,
        mint_flag: vector<u8>,
        ctx: &mut TxContext
    ) {
        let nft_name = string::utf8(name);
        let nft_image = url::new_unsafe_from_bytes(image);
        let nft = NFTObject {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            image: nft_image,
            name: nft_name,
            mint_flag: mint_flag,
            position_x: 0,
            position_y: 0
        };
        // イベント発行に必要なフィールドを展開
        let nft_id = sui::object::uid_to_inner(&nft.id);
        let owner = nft.owner;
        let name_val = nft.name;
        event::emit(MintNFTObjectEvent {
            nft_id: nft_id,
            owner: owner,
            name: name_val
        });
        transfer::public_transfer(nft, owner);
    }

    /// 複数の NFTObject を連携して SynObject を mint する  
    /// - `attached_objects`: 連携対象の NFTObject の ID 一覧  
    /// - `image`: SynObject 用画像 URI（バイトベクター）  
    /// - `mint_flags`: 連携対象各 NFT の mint_flag 情報（各バイトベクターのリスト）
    public entry fun mint_syn_object(
        attached_objects: vector<ID>,
        image: vector<u8>,
        mint_flags: vector<vector<u8>>,
        ctx: &mut TxContext
    ) {
        let syn_image = url::new_unsafe_from_bytes(image);
        let syn = SynObject {
            id: sui::object::new(ctx),
            owner: sui::tx_context::sender(ctx),
            attached_objects: attached_objects,
            image: syn_image,
            mint_flags: mint_flags,
            is_public: false
        };
        event::emit(MintSynObjectEvent {
            syn_id: sui::object::uid_to_inner(&syn.id),
            creator: sui::tx_context::sender(ctx)
        });
        transfer::public_transfer(syn, sui::tx_context::sender(ctx));
    }

    /// SynObject の公開状態を更新する
    public entry fun publish_syn_object(
        syn: &mut SynObject,
        ctx: &mut TxContext
    ) {
        syn.is_public = true;
    }

    /////////////////////////////////
    // Getter Functions
    /////////////////////////////////

    public fun get_tank_owner(tank: &WaterTank): address {
        tank.owner
    }

    public fun get_nft_name(nft: &NFTObject): &string::String {
        &nft.name
    }

    public fun syn_object_is_public(syn: &SynObject): bool {
        syn.is_public
    }
}

#[test_only]
module suiden::nft_systemTests {
    use suiden::nft_system::{
        WaterTank, NFTObject, initialize_tank, mint_nft_object,
        attach_object, update_object_position
    };
    use sui::test_scenario as ts;
    use sui::transfer;
    use std::string;

    #[test]
    fun test_tank_nft_workflow() {
        let addr1 = @0xA;
        // addr1 を作成者としてシナリオ開始
        let scenario = ts::begin(addr1);
        {
            // 1. ウォータータンクの初期化
            initialize_tank(
                addr1,
                b"https://example.com/bg.png",
                1,
                ts::ctx(&mut scenario)
            );
        };
        
        // トランザクションを完了させる
        ts::next_tx(&mut scenario, addr1);
        {
            // 送信先アドレス (addr1) の在庫から取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);

            // 2. NFTObject の mint
            mint_nft_object(
                b"TestNFT",
                b"https://example.com/nft.png",
                b"flag",
                ts::ctx(&mut scenario)
            );
            
            // タンクをアドレスに戻す
            ts::return_to_address(addr1, tank);
        };
        
        // 次のトランザクションに移行
        ts::next_tx(&mut scenario, addr1);
        {
            // 送信先アドレス (addr1) の在庫からタンクと NFT を取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let nft = ts::take_from_address<NFTObject>(&scenario, addr1);

            // 3. NFTObject をウォータータンクに添付
            attach_object(&mut tank, &mut nft, ts::ctx(&mut scenario));

            // 4. NFTObject の位置を更新（例：x=100, y=200）
            update_object_position(&tank, &mut nft, 100, 200, ts::ctx(&mut scenario));

            // 5. 各リソースを送信者に返却
            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, nft);
        };

        ts::end(scenario);
    }
}