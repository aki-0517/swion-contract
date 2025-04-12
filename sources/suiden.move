module suiden::nft_system {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url::{Self, Url};
    use std::string::{Self, String};
    use std::vector;
    use sui::dynamic_object_field as dof;
    use sui::table::{Self, Table};

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
        background_image: Url,
        // 現在のレベル
        level: u64
    }

    /// NFT情報を格納する構造体（取得用）
    struct NFTInfo has store, drop, copy {
        id: ID,
        name: String,
        image: Url,
        position_x: u64,
        position_y: u64
    }

    /// 複数のNFT情報をまとめて返すための構造体
    struct NFTCollection has store, drop {
        nfts: vector<NFTInfo>
    }

    /// 個々のNFT Objectを表す構造体
    /// UID を含むため drop 能力は付与しません
    struct NFTObject has key, store {
        id: UID,
        owner: address,
        image: Url,
        name: String,
        // NFTObject の配置情報: x軸と y軸
        position_x: u64,
        position_y: u64
    }

    /// 複数のNFT Objectを連携した SynObject の構造体
    struct SynObject has key, store {
        id: UID,
        owner: address,
        // 連携する NFTObject の ID 一覧
        attached_objects: vector<ID>,
        image: Url,
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
        name: String
    }

    struct MintSynObjectEvent has copy, drop {
        syn_id: ID,
        creator: address
    }

    // 追加: 背景画像とレベル更新イベント
    struct UpdateTankBackgroundEvent has copy, drop {
        tank_id: ID,
        new_background: Url
    }

    struct UpdateTankLevelEvent has copy, drop {
        tank_id: ID,
        new_level: u64
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
            id: object::new(ctx),
            owner,
            child_objects: vector::empty<ID>(),
            background_image: bg_url,
            level
        };
        event::emit(MintWaterTankEvent {
            tank_id: object::uid_to_inner(&tank.id),
            owner
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
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみが更新可能
        assert!(sender == tank.owner, 1);
        nft.position_x = new_x;
        nft.position_y = new_y;
        event::emit(UpdateObjectPositionEvent {
            nft_id: object::uid_to_inner(&nft.id),
            new_x,
            new_y
        });
    }

    /// ウォータータンクに NFTObject を添付する  
    /// NFTObject は mutable reference で受け取ることで、値の move を避けます
    /// 修正: 重複チェックを追加
    public entry fun attach_object(
        tank: &mut WaterTank,
        nft: &mut NFTObject,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーであることをチェック
        assert!(sender == tank.owner, 2);
        let nft_id = object::uid_to_inner(&nft.id);
        
        // 重複チェック - 既に添付済みの場合はスキップ
        if (!vector::contains(&tank.child_objects, &nft_id)) {
            vector::push_back(&mut tank.child_objects, nft_id);
            event::emit(AttachObjectEvent {
                tank_id: object::uid_to_inner(&tank.id),
                object_id: nft_id
            });
        };
    }

    /// 個々の NFTObject の mint  
    /// - `name`: NFT の名称（バイトベクター）  
    /// - `image`: 画像 URI（バイトベクター）  
    public entry fun mint_nft_object(
        name: vector<u8>,
        image: vector<u8>,
        ctx: &mut TxContext
    ) {
        let nft_name = string::utf8(name);
        let nft_image = url::new_unsafe_from_bytes(image);
        let nft = NFTObject {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            image: nft_image,
            name: nft_name,
            position_x: 0,
            position_y: 0
        };
        let nft_id = object::uid_to_inner(&nft.id);
        let owner = nft.owner;
        let name_val = nft.name;
        event::emit(MintNFTObjectEvent {
            nft_id,
            owner,
            name: name_val
        });
        transfer::public_transfer(nft, owner);
    }

    /// 複数の NFTObject を連携して SynObject を mint する  
    /// - `attached_objects`: 連携対象の NFTObject の ID 一覧  
    /// - `image`: SynObject 用画像 URI（バイトベクター）  
    public entry fun mint_syn_object(
        attached_objects: vector<ID>,
        image: vector<u8>,
        ctx: &mut TxContext
    ) {
        let syn_image = url::new_unsafe_from_bytes(image);
        let syn = SynObject {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            attached_objects,
            image: syn_image,
            is_public: false
        };
        event::emit(MintSynObjectEvent {
            syn_id: object::uid_to_inner(&syn.id),
            creator: tx_context::sender(ctx)
        });
        transfer::public_transfer(syn, tx_context::sender(ctx));
    }

    /// SynObject の公開状態を更新する
    public entry fun publish_syn_object(
        syn: &mut SynObject,
        ctx: &mut TxContext
    ) {
        syn.is_public = true;
    }

    /// 追加: SBTの背景画像を更新する
    public entry fun update_tank_background(
        tank: &mut WaterTank,
        new_background: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみが更新可能
        assert!(sender == tank.owner, 3);
        
        let bg_url = url::new_unsafe_from_bytes(new_background);
        tank.background_image = bg_url;
        
        event::emit(UpdateTankBackgroundEvent {
            tank_id: object::uid_to_inner(&tank.id),
            new_background: bg_url
        });
    }

    /// 追加: SBTのレベルを更新する
    public entry fun update_tank_level(
        tank: &mut WaterTank,
        new_level: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみが更新可能
        assert!(sender == tank.owner, 4);
        
        tank.level = new_level;
        
        event::emit(UpdateTankLevelEvent {
            tank_id: object::uid_to_inner(&tank.id),
            new_level
        });
    }

    /// 修正: save_layout 関数でも child_objects を更新するよう変更
    /// - `tank`: 更新対象のウォータータンクSBT（mutable 参照に変更）
    /// - `nft`: 更新対象の NFTObject  
    public entry fun save_layout(
        tank: &mut WaterTank, // &WaterTank から &mut WaterTank に変更
        nft: &mut NFTObject,
        new_x: u64,
        new_y: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみ更新可能
        assert!(sender == tank.owner, 5);
        
        // NFTの位置を更新
        nft.position_x = new_x;
        nft.position_y = new_y;
        
        // NFTがまだタンクに添付されていない場合は追加
        let nft_id = object::uid_to_inner(&nft.id);
        if (!vector::contains(&tank.child_objects, &nft_id)) {
            vector::push_back(&mut tank.child_objects, nft_id);
            event::emit(AttachObjectEvent {
                tank_id: object::uid_to_inner(&tank.id),
                object_id: nft_id
            });
        };
        
        event::emit(UpdateObjectPositionEvent {
            nft_id,
            new_x,
            new_y
        });
    }

    // Getter Functions

    /// ウォレットアドレスからSBTに紐付いたNFT Objectの情報を全て取得する
    /// オブジェクトコレクションとして返す
    /// ※引数のnftsベクターは関数内で消費されるため、呼び出し側で再利用できなくなります
    public fun get_wallet_nft_collection(
        tank: &WaterTank,
        nfts: vector<NFTObject>
    ): (NFTCollection, vector<NFTObject>) {
        let len = vector::length(&nfts);
        let result = vector::empty<NFTInfo>();
        let remaining_nfts = vector::empty<NFTObject>();
        
        let i = 0;
        while (i < len) {
            let nft = vector::pop_back(&mut nfts);
            let nft_id = object::uid_to_inner(&nft.id);
            
            if (vector::contains(&tank.child_objects, &nft_id)) {
                vector::push_back(&mut result, NFTInfo {
                    id: nft_id,
                    name: nft.name,
                    image: nft.image,
                    position_x: nft.position_x,
                    position_y: nft.position_y
                });
            };
            
            vector::push_back(&mut remaining_nfts, nft);
            i = i + 1;
        };

        vector::destroy_empty(nfts);
        (NFTCollection { nfts: result }, remaining_nfts)
    }

    /// NFTCollectionから個々のNFT情報を取得する
    public fun get_nft_info_from_collection(collection: &NFTCollection, index: u64): &NFTInfo {
        vector::borrow(&collection.nfts, index)
    }

    /// NFTCollectionのサイズを取得する
    public fun get_collection_size(collection: &NFTCollection): u64 {
        vector::length(&collection.nfts)
    }

    /// NFT情報から名前を取得
    public fun get_nft_info_name(info: &NFTInfo): String {
        info.name
    }

    /// NFT情報から画像URLを取得
    public fun get_nft_info_image(info: &NFTInfo): Url {
        info.image
    }

    /// NFT情報から位置を取得
    public fun get_nft_info_position(info: &NFTInfo): (u64, u64) {
        (info.position_x, info.position_y)
    }

    /// NFT情報からIDを取得
    public fun get_nft_info_id(info: &NFTInfo): ID {
        info.id
    }

    #[allow(unused_use)]
    public fun get_tank_child_objects(tank: &WaterTank): &vector<ID> {
        &tank.child_objects
    }

    #[allow(unused_use)]
    public fun get_tank_background(tank: &WaterTank): &Url {
        &tank.background_image
    }

    #[allow(unused_use)]
    public fun get_tank_level(tank: &WaterTank): u64 {
        tank.level
    }

    #[allow(unused_use)]
    public fun get_nft_position(nft: &NFTObject): (u64, u64) {
        (nft.position_x, nft.position_y)
    }

    #[allow(unused_use)]
    public fun get_nft_image(nft: &NFTObject): &Url {
        &nft.image
    }

    #[allow(unused_use)]
    public fun get_nft_owner(nft: &NFTObject): address {
        nft.owner
    }

    #[allow(unused_use)]
    public fun get_syn_attached_objects(syn: &SynObject): &vector<ID> {
        &syn.attached_objects
    }

    #[allow(unused_use)]
    public fun get_syn_owner(syn: &SynObject): address {
        syn.owner
    }

    #[allow(unused_use)]
    public fun get_syn_image(syn: &SynObject): &Url {
        &syn.image
    }

    #[allow(unused_use)]
    public fun get_tank_id(tank: &WaterTank): ID {
        object::uid_to_inner(&tank.id)
    }

    #[allow(unused_use)]
    public fun get_tank_owner(tank: &WaterTank): address {
        tank.owner
    }
}