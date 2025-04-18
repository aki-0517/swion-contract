module swion::nft_system {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url::{Self, Url};
    use std::string::{Self, String};
    use std::vector;
    use sui::display::{Self, Display}; // Added display import
    use sui::package::{Self, Publisher}; // Added package import
    use sui::hex; // Added hex import for address encoding
    use sui::bcs; // Added bcs import for address conversion
    use std::option::{Self, Option}; // 追加: Optionタイプのために必要
    // Kiosk関連の追加インポート
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer_policy::{Self, TransferPolicy, TransferPolicyCap};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::table::{Self, Table}; // 追加: Kioskの価格テーブル用
    use swion::marketplace; // 追加

    /////////////////////////////////
    // Structures
    /////////////////////////////////

    /// OTW (One Time Witness) for display initialization
    struct NFT_SYSTEM has drop {}

    /// Kiosk価格管理のためのオブジェクト
    struct KioskPriceRegistry has key, store {
        id: UID,
        // Kiosk ID -> 価格のマッピング
        prices: Table<ID, u64>
    }

    /// ウォータータンクSBTの構造体
    struct WaterTank has key, store {
        id: UID,
        owner: address,
        // タンクに添付されたNFT ObjectのID一覧
        child_objects: vector<ID>,
        // 背景画像URI（walrus保存用）
        background_image: Url,
        // 現在のレベル
        level: u64,
        // Hex-encoded ID for Walrus site references
        hexaddr: String,
        custom_walrus_site: Option<address> // 新しいフィールド
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
        is_public: bool,
        // 総供給量の設定
        max_supply: u64,
        // 現在の発行数
        current_supply: u64,
        // 販売価格
        price: u64,
        // SynObjectの位置情報
        position_x: u64,
        position_y: u64
    }

    /// タンクにSynObjectを添付するイベント
    struct AttachSynObjectEvent has copy, drop {
        tank_id: ID,
        syn_id: ID
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

    // Kioskに関連する新しいイベント
    struct PlaceSynObjectInKioskEvent has copy, drop {
        syn_id: ID,
        kiosk_id: ID,
        price: u64
    }

    struct PurchaseSynObjectEvent has copy, drop {
        syn_id: ID,
        buyer: address,
        price: u64
    }

    // SynObjectの位置情報更新用イベント
    struct UpdateSynPositionEvent has copy, drop {
        syn_id: ID,
        new_x: u64,
        new_y: u64
    }

    /////////////////////////////////
    // Module Initialization
    /////////////////////////////////

    /// Module initialization function - sets up the Display for WaterTank objects and Kiosk registry
    fun init(otw: NFT_SYSTEM, ctx: &mut TxContext) {
        let publisher = package::claim(otw, ctx);
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

        // Kiosk価格レジストリの初期化
        let kiosk_registry = KioskPriceRegistry {
            id: object::new(ctx),
            prices: table::new(ctx)
        };
        
        transfer::public_transfer(publisher, tx_context::sender(ctx));
        transfer::public_transfer(display, tx_context::sender(ctx));
        transfer::public_share_object(kiosk_registry);
    }

    /// Walrus Siteアドレスを設定/更新する関数
    public entry fun set_custom_walrus_site(
        tank: &mut WaterTank, 
        walrus_site_address: address,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == tank.owner, 100);
        tank.custom_walrus_site = option::some(walrus_site_address);
    }

    /// カスタムWalrus Siteアドレスを取得する関数
    public fun get_walrus_site_address(tank: &WaterTank): address {
        *option::borrow_with_default(
            &tank.custom_walrus_site, 
            &tank.owner
        )
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
        let id = object::new(ctx);
        let id_bytes = object::uid_to_bytes(&id);
        let hex_encoded = hex::encode(id_bytes);
        let hexaddr = string::utf8(hex_encoded);
        let bg_url = url::new_unsafe_from_bytes(background_image);
        
        let tank = WaterTank {
            id,
            owner,
            child_objects: vector::empty<ID>(),
            background_image: bg_url,
            level,
            hexaddr,
            custom_walrus_site: option::none()
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
    /// - `max_supply`: 最大供給量  
    /// - `price`: 販売価格
    public entry fun mint_syn_object(
        attached_objects: vector<ID>,
        image: vector<u8>,
        max_supply: u64,
        price: u64,
        ctx: &mut TxContext
    ) {
        let syn_image = url::new_unsafe_from_bytes(image);
        let syn = SynObject {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            attached_objects,
            image: syn_image,
            is_public: false,
            max_supply,
            current_supply: 1, // 初期発行数は1
            price,
            position_x: 0, // 初期位置は0,0
            position_y: 0
        };
        event::emit(MintSynObjectEvent {
            syn_id: object::uid_to_inner(&syn.id),
            creator: tx_context::sender(ctx)
        });
        transfer::public_transfer(syn, tx_context::sender(ctx));
    }

    /// SynObjectのTransferPolicyを初期化する関数
    public entry fun init_syn_object_transfer_policy(
        publisher: &Publisher,
        ctx: &mut TxContext
    ) {
        let (transfer_policy, cap) = transfer_policy::new<SynObject>(publisher, ctx);
        // TransferPolicyを共有オブジェクトとして公開
        transfer::public_share_object(transfer_policy);
        // TransferPolicyCopはポリシー管理者に送信
        transfer::public_transfer(cap, tx_context::sender(ctx));
    }

    /// SynObjectをKioskに配置する関数
    public entry fun place_syn_object_in_kiosk(
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
        syn: SynObject,
        policy: &TransferPolicy<SynObject>,
        ctx: &mut TxContext
    ) {
        // オーナーチェック
        assert!(tx_context::sender(ctx) == syn.owner, 1000);
        // 供給量チェック
        assert!(syn.current_supply <= syn.max_supply, 1001);
        
        let syn_id = object::uid_to_inner(&syn.id);
        let price = syn.price;
        
        // オブジェクトをキオスクに配置して出品
        kiosk::place_and_list(kiosk, cap, syn, price);
        
        event::emit(PlaceSynObjectInKioskEvent {
            syn_id,
            kiosk_id: object::id(kiosk),
            price
        });
    }

    /// SynObjectをKioskから購入する関数
    public entry fun purchase_syn_object_from_kiosk(
        kiosk: &mut Kiosk,
        policy: &TransferPolicy<SynObject>,
        syn_id: ID,
        payment: Coin<SUI>,
        ctx: &mut TxContext
    ) {
        // キオスクからの購入処理
        let (syn, request) = kiosk::purchase<SynObject>(kiosk, syn_id, payment);
        
        // 供給量の更新
        syn.current_supply = syn.current_supply + 1;
        
        // TransferPolicyの確認
        transfer_policy::confirm_request(policy, request);
        
        let buyer = tx_context::sender(ctx);
        event::emit(PurchaseSynObjectEvent {
            syn_id,
            buyer,
            price: syn.price
        });
        
        // 購入者に転送
        transfer::public_transfer(syn, buyer);
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

    /// ウォータータンクにSynObjectを添付する
    public entry fun attach_syn_object(
        tank: &mut WaterTank,
        syn: &SynObject,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーであることをチェック
        assert!(sender == tank.owner, 2);
        let syn_id = object::uid_to_inner(&syn.id);
        
        // 重複チェック - 既に添付済みの場合はスキップ
        if (!vector::contains(&tank.child_objects, &syn_id)) {
            vector::push_back(&mut tank.child_objects, syn_id);
            event::emit(AttachSynObjectEvent {
                tank_id: object::uid_to_inner(&tank.id),
                syn_id
            });
        };
    }

    // Getter Functions

    /// Kioskの価格を取得する
    public fun get_kiosk_price(registry: &KioskPriceRegistry, kiosk_id: ID): Option<u64> {
        if (table::contains(&registry.prices, kiosk_id)) {
            option::some(*table::borrow(&registry.prices, kiosk_id))
        } else {
            option::none()
        }
    }

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

    /// タンクのhexアドレスを取得
    public fun get_tank_hexaddr(tank: &WaterTank): String {
        tank.hexaddr
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

    // SynObjectの供給量関連の新しいgetter関数
    #[allow(unused_use)]
    public fun get_syn_current_supply(syn: &SynObject): u64 {
        syn.current_supply
    }

    #[allow(unused_use)]
    public fun get_syn_max_supply(syn: &SynObject): u64 {
        syn.max_supply
    }

    #[allow(unused_use)]
    public fun get_syn_price(syn: &SynObject): u64 {
        syn.price
    }

    #[allow(unused_use)]
    public fun get_tank_id(tank: &WaterTank): ID {
        object::uid_to_inner(&tank.id)
    }

    #[allow(unused_use)]
    public fun get_tank_owner(tank: &WaterTank): address {
        tank.owner
    }

    /// SynObjectのコレクション情報
    struct SynInfo has store, drop, copy {
        id: ID,
        image: Url,
        is_public: bool,
        max_supply: u64,
        current_supply: u64,
        price: u64,
        // 位置情報を追加
        position_x: u64,
        position_y: u64
    }

    /// SynObjectコレクション
    struct SynCollection has store, drop {
        syns: vector<SynInfo>
    }

    /// ウォレットアドレスからSBTに紐付いたSynObjectの情報を全て取得する
    public fun get_wallet_syn_collection(
        tank: &WaterTank,
        syns: vector<SynObject>
    ): (SynCollection, vector<SynObject>) {
        let len = vector::length(&syns);
        let result = vector::empty<SynInfo>();
        let remaining_syns = vector::empty<SynObject>();
        
        let i = 0;
        while (i < len) {
            let syn = vector::pop_back(&mut syns);
            let syn_id = object::uid_to_inner(&syn.id);
            
            if (vector::contains(&tank.child_objects, &syn_id)) {
                vector::push_back(&mut result, SynInfo {
                    id: syn_id,
                    image: syn.image,
                    is_public: syn.is_public,
                    max_supply: syn.max_supply,
                    current_supply: syn.current_supply,
                    price: syn.price,
                    position_x: syn.position_x,
                    position_y: syn.position_y
                });
            };
            
            vector::push_back(&mut remaining_syns, syn);
            i = i + 1;
        };

        vector::destroy_empty(syns);
        (SynCollection { syns: result }, remaining_syns)
    }

    /// SynCollectionから個々のSyn情報を取得する
    public fun get_syn_info_from_collection(collection: &SynCollection, index: u64): &SynInfo {
        vector::borrow(&collection.syns, index)
    }

    /// SynCollectionのサイズを取得する
    public fun get_syn_collection_size(collection: &SynCollection): u64 {
        vector::length(&collection.syns)
    }

    /// Syn情報からIDを取得
    public fun get_syn_info_id(info: &SynInfo): ID {
        info.id
    }

    /// Syn情報から画像URLを取得
    public fun get_syn_info_image(info: &SynInfo): Url {
        info.image
    }

    /// Syn情報から公開状態を取得
    public fun get_syn_info_is_public(info: &SynInfo): bool {
        info.is_public
    }

    /// Syn情報から供給量情報を取得
    public fun get_syn_info_supply(info: &SynInfo): (u64, u64) {
        (info.current_supply, info.max_supply)
    }

    /// Syn情報から価格を取得
    public fun get_syn_info_price(info: &SynInfo): u64 {
        info.price
    }

    /// Syn情報から位置情報を取得
    public fun get_syn_info_position(info: &SynInfo): (u64, u64) {
        (info.position_x, info.position_y)
    }

    // テスト用のヘルパー関数
    #[test_only]
    public fun get_syn_id(syn: &SynObject): ID {
        object::uid_to_inner(&syn.id)
    }

    #[test_only]
    public fun create_test_nft(ctx: &mut TxContext): SynObject {
        SynObject {
            id: object::new(ctx),
            owner: tx_context::sender(ctx),
            attached_objects: vector::empty(),
            image: url::new_unsafe_from_bytes(b"https://example.com/test.png"),
            is_public: false,
            max_supply: 100,
            current_supply: 1,
            price: 1000,
            position_x: 0,
            position_y: 0
        }
    }

    /// SynObjectの位置を更新する関数
    public entry fun update_syn_position(
        tank: &WaterTank,
        syn: &mut SynObject,
        new_x: u64,
        new_y: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみが更新可能
        assert!(sender == tank.owner, 1);
        syn.position_x = new_x;
        syn.position_y = new_y;
        event::emit(UpdateSynPositionEvent {
            syn_id: object::uid_to_inner(&syn.id),
            new_x,
            new_y
        });
    }

    /// SynObjectの位置情報を取得する関数
    #[allow(unused_use)]
    public fun get_syn_position(syn: &SynObject): (u64, u64) {
        (syn.position_x, syn.position_y)
    }
}

#[test_only]
module swion::nft_systemTests {
    use swion::nft_system::{
        Self, WaterTank, NFTObject, SynObject,
        initialize_tank, mint_nft_object, mint_syn_object,
        attach_object, update_object_position, update_tank_background,
        update_tank_level, save_layout, attach_syn_object, get_syn_id,
        update_syn_position, get_syn_position
    };
    use sui::test_scenario as ts;
    use sui::object;
    use std::vector;
    use sui::tx_context;
    use sui::url;

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

        ts::next_tx(&mut scenario, addr1);
        {
            // 送信先アドレス (addr1) の在庫から取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);

            // 2. NFTObject の mint
            mint_nft_object(
                b"TestNFT",
                b"https://example.com/nft.png",
                ts::ctx(&mut scenario)
            );

            ts::return_to_address(addr1, tank);
        };

        ts::next_tx(&mut scenario, addr1);
        {
            // 送信先アドレス (addr1) の在庫からタンクと NFT を取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let nft = ts::take_from_address<NFTObject>(&scenario, addr1);

            // 3. NFTObject をウォータータンクに添付
            attach_object(&mut tank, &mut nft, ts::ctx(&mut scenario));

            // 4. NFTObject の位置を個別更新（例：x=100, y=200）
            update_object_position(&tank, &mut nft, 100, 200, ts::ctx(&mut scenario));

            // 5. 新機能テスト：NFTの位置を更新
            save_layout(&mut tank, &mut nft, 120, 250, ts::ctx(&mut scenario));

            // 新機能テスト：背景とレベルの更新
            update_tank_background(&mut tank, b"https://example.com/new_bg.png", ts::ctx(&mut scenario));
            update_tank_level(&mut tank, 2, ts::ctx(&mut scenario));

            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, nft);
        };

        ts::next_tx(&mut scenario, addr1);
        {
            // 新機能テスト：SBTに紐付いたNFT情報の取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let nft = ts::take_from_address<NFTObject>(&scenario, addr1);
            
            // NFTオブジェクトをベクターに格納
            let nfts = vector::empty<NFTObject>();
            vector::push_back(&mut nfts, nft);
            
            // NFTコレクションを取得 (nftsの所有権は関数内で消費され、新しいベクターとして返される)
            let (collection, returned_nfts) = nft_system::get_wallet_nft_collection(&tank, nfts);
            
            // コレクションのサイズを確認（期待値: 1）
            let size = nft_system::get_collection_size(&collection);
            assert!(size == 1, 101);
            
            // 最初のNFTの情報を取得
            let nft_info = nft_system::get_nft_info_from_collection(&collection, 0);
            
            // NFT情報から各値を取得して検証
            let name = nft_system::get_nft_info_name(nft_info);
            let (x, y) = nft_system::get_nft_info_position(nft_info);
            
            // 名前と位置が期待通りか確認
            assert!(name == std::string::utf8(b"TestNFT"), 102);
            assert!(x == 120 && y == 250, 103);
            
            // コレクションはdrop能力があるので明示的な破棄は不要
            
            // 返された新しいベクターからNFTを取り出す
            assert!(vector::length(&returned_nfts) == 1, 104);
            let returned_nft = vector::pop_back(&mut returned_nfts);
            
            // 空になったベクターを破棄
            vector::destroy_empty(returned_nfts);
            
            // 返却
            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, returned_nft);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_tank_syn_object_workflow() {
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

        ts::next_tx(&mut scenario, addr1);
        {
            // 2. SynObject の mint
            // 空のattached_objectsベクターを作成
            let attached_objects = vector::empty<object::ID>();
            
            mint_syn_object(
                attached_objects,
                b"https://example.com/syn.png",
                100, // max_supply
                1000, // price
                ts::ctx(&mut scenario)
            );
        };

        ts::next_tx(&mut scenario, addr1);
        {
            // 送信先アドレス (addr1) の在庫からタンクと SynObject を取得
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let syn = ts::take_from_address<SynObject>(&scenario, addr1);

            // 3. SynObject をウォータータンクに添付
            attach_syn_object(&mut tank, &syn, ts::ctx(&mut scenario));
            
            // タンクにSynObjectのIDが追加されていることを確認
            let tank_objects = nft_system::get_tank_child_objects(&tank);
            let syn_id = nft_system::get_syn_id(&syn);
            
            // SynObjectのIDがタンクのchild_objectsに含まれていることを確認
            assert!(vector::contains(tank_objects, &syn_id), 200);

            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, syn);
        };

        ts::next_tx(&mut scenario, addr1);
        {
            // SBTに紐付いたSynObject情報の取得をテスト
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let syn = ts::take_from_address<SynObject>(&scenario, addr1);
            
            // SynObjectをベクターに格納
            let syns = vector::empty<SynObject>();
            vector::push_back(&mut syns, syn);
            
            // SynCollectionを取得
            let (collection, returned_syns) = nft_system::get_wallet_syn_collection(&tank, syns);
            
            // コレクションのサイズを確認（期待値: 1）
            let size = nft_system::get_syn_collection_size(&collection);
            assert!(size == 1, 201);
            
            // 最初のSynObjectの情報を取得
            let syn_info = nft_system::get_syn_info_from_collection(&collection, 0);
            
            // SynInfo情報から各値を取得して検証
            let is_public = nft_system::get_syn_info_is_public(syn_info);
            let (current_supply, max_supply) = nft_system::get_syn_info_supply(syn_info);
            let price = nft_system::get_syn_info_price(syn_info);
            
            // 値が期待通りか確認
            assert!(!is_public, 202); // 初期状態ではfalse
            assert!(current_supply == 1 && max_supply == 100, 203);
            assert!(price == 1000, 204);
            
            // 返された新しいベクターからSynObjectを取り出す
            assert!(vector::length(&returned_syns) == 1, 205);
            let returned_syn = vector::pop_back(&mut returned_syns);
            
            // 空になったベクターを破棄
            vector::destroy_empty(returned_syns);
            
            // 返却
            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, returned_syn);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_syn_object_position() {
        let addr1 = @0xA;
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

        ts::next_tx(&mut scenario, addr1);
        {
            // 2. SynObject の mint
            let attached_objects = vector::empty<object::ID>();
            
            mint_syn_object(
                attached_objects,
                b"https://example.com/syn.png",
                100,
                1000,
                ts::ctx(&mut scenario)
            );
        };

        ts::next_tx(&mut scenario, addr1);
        {
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let syn = ts::take_from_address<SynObject>(&scenario, addr1);

            // 3. SynObjectをタンクに添付
            attach_syn_object(&mut tank, &syn, ts::ctx(&mut scenario));
            
            // 4. SynObjectの位置を更新
            update_syn_position(&tank, &mut syn, 150, 300, ts::ctx(&mut scenario));
            
            // 位置が正しく更新されたか確認
            let (x, y) = nft_system::get_syn_position(&syn);
            assert!(x == 150 && y == 300, 300);

            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, syn);
        };

        ts::next_tx(&mut scenario, addr1);
        {
            let tank = ts::take_from_address<WaterTank>(&scenario, addr1);
            let syn = ts::take_from_address<SynObject>(&scenario, addr1);
            
            // SynObjectをベクターに格納
            let syns = vector::empty<SynObject>();
            vector::push_back(&mut syns, syn);
            
            // SynCollectionを取得
            let (collection, returned_syns) = nft_system::get_wallet_syn_collection(&tank, syns);
            
            // 最初のSynObjectの情報を取得
            let syn_info = nft_system::get_syn_info_from_collection(&collection, 0);
            
            // 位置情報が正しく含まれているか確認
            let (info_x, info_y) = nft_system::get_syn_info_position(syn_info);
            assert!(info_x == 150 && info_y == 300, 301);
            
            // 返却処理
            let returned_syn = vector::pop_back(&mut returned_syns);
            vector::destroy_empty(returned_syns);
            
            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, returned_syn);
        };

        ts::end(scenario);
    }
}