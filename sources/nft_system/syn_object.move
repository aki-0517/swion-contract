module swion::nft_system_syn_object {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url::{Self, Url};
    use std::vector;

    use swion::nft_system_water_tank::{Self as water_tank, WaterTank};
    use swion::nft_system_types::{SynInfo, SynCollection, create_syn_info, create_syn_collection};

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

    struct MintSynObjectEvent has copy, drop {
        syn_id: ID,
        creator: address
    }

    struct UpdateSynPositionEvent has copy, drop {
        syn_id: ID,
        new_x: u64,
        new_y: u64
    }

    /// 複数の NFTObject を連携して SynObject を mint する
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

    /// SynObject の公開状態を更新する
    public entry fun publish_syn_object(
        syn: &mut SynObject,
        _ctx: &mut TxContext
    ) {
        syn.is_public = true;
    }

    /// ウォータータンクにSynObjectを添付する
    public entry fun attach_syn_object(
        tank: &mut WaterTank,
        syn: &SynObject,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーであることをチェック
        assert!(sender == water_tank::get_tank_owner(tank), 2);
        let syn_id = object::uid_to_inner(&syn.id);
        
        // WaterTankモジュールの関数を使用して追加
        water_tank::add_syn_to_tank(tank, syn_id);
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
        assert!(sender == water_tank::get_tank_owner(tank), 1);
        syn.position_x = new_x;
        syn.position_y = new_y;
        event::emit(UpdateSynPositionEvent {
            syn_id: object::uid_to_inner(&syn.id),
            new_x,
            new_y
        });
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
            
            if (water_tank::contains_object(tank, &syn_id)) {
                let info = create_syn_info(
                    syn_id,
                    syn.image,
                    syn.is_public,
                    syn.max_supply,
                    syn.current_supply,
                    syn.price,
                    syn.position_x,
                    syn.position_y
                );
                vector::push_back(&mut result, info);
            };
            
            vector::push_back(&mut remaining_syns, syn);
            i = i + 1;
        };

        vector::destroy_empty(syns);
        (create_syn_collection(result), remaining_syns)
    }

    // Getter関数
    public fun get_syn_attached_objects(syn: &SynObject): &vector<ID> {
        &syn.attached_objects
    }

    public fun get_syn_owner(syn: &SynObject): address {
        syn.owner
    }

    public fun get_syn_image(syn: &SynObject): &Url {
        &syn.image
    }

    public fun get_syn_current_supply(syn: &SynObject): u64 {
        syn.current_supply
    }

    public fun get_syn_max_supply(syn: &SynObject): u64 {
        syn.max_supply
    }

    public fun get_syn_price(syn: &SynObject): u64 {
        syn.price
    }

    public fun get_syn_position(syn: &SynObject): (u64, u64) {
        (syn.position_x, syn.position_y)
    }

    public fun get_syn_is_public(syn: &SynObject): bool {
        syn.is_public
    }

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
} 