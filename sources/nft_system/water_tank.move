module swion::nft_system_water_tank {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url::{Self, Url};
    use std::string::{Self, String};
    use std::vector;
    use std::option::{Self, Option};
    use sui::hex;

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
        custom_walrus_site: Option<address>
    }

    /// タンクにSynObjectを添付するイベント
    struct AttachSynObjectEvent has copy, drop {
        tank_id: ID,
        syn_id: ID
    }

    struct AttachObjectEvent has copy, drop {
        tank_id: ID,
        object_id: ID
    }

    struct MintWaterTankEvent has copy, drop {
        tank_id: ID,
        owner: address
    }

    struct UpdateTankBackgroundEvent has copy, drop {
        tank_id: ID,
        new_background: Url
    }

    struct UpdateTankLevelEvent has copy, drop {
        tank_id: ID,
        new_level: u64
    }

    /// 新規ウォータータンクSBTの初期化
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

    /// 背景画像を更新する
    public entry fun update_tank_background(
        tank: &mut WaterTank,
        new_background: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == tank.owner, 3);
        
        let bg_url = url::new_unsafe_from_bytes(new_background);
        tank.background_image = bg_url;
        
        event::emit(UpdateTankBackgroundEvent {
            tank_id: object::uid_to_inner(&tank.id),
            new_background: bg_url
        });
    }

    /// レベルを更新する
    public entry fun update_tank_level(
        tank: &mut WaterTank,
        new_level: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        assert!(sender == tank.owner, 4);
        
        tank.level = new_level;
        
        event::emit(UpdateTankLevelEvent {
            tank_id: object::uid_to_inner(&tank.id),
            new_level
        });
    }

    /// NFTをタンクに追加する
    public fun add_nft_to_tank(
        tank: &mut WaterTank,
        nft_id: ID
    ) {
        if (!vector::contains(&tank.child_objects, &nft_id)) {
            vector::push_back(&mut tank.child_objects, nft_id);
            event::emit(AttachObjectEvent {
                tank_id: object::uid_to_inner(&tank.id),
                object_id: nft_id
            });
        };
    }

    /// SynObjectをタンクに追加する
    public fun add_syn_to_tank(
        tank: &mut WaterTank,
        syn_id: ID
    ) {
        if (!vector::contains(&tank.child_objects, &syn_id)) {
            vector::push_back(&mut tank.child_objects, syn_id);
            event::emit(AttachSynObjectEvent {
                tank_id: object::uid_to_inner(&tank.id),
                syn_id
            });
        };
    }

    // Getter Functions
    public fun get_tank_hexaddr(tank: &WaterTank): String {
        tank.hexaddr
    }

    public fun get_tank_child_objects(tank: &WaterTank): &vector<ID> {
        &tank.child_objects
    }

    public fun get_tank_background(tank: &WaterTank): &Url {
        &tank.background_image
    }

    public fun get_tank_level(tank: &WaterTank): u64 {
        tank.level
    }

    public fun get_tank_id(tank: &WaterTank): ID {
        object::uid_to_inner(&tank.id)
    }

    public fun get_tank_owner(tank: &WaterTank): address {
        tank.owner
    }

    public fun contains_object(tank: &WaterTank, id: &ID): bool {
        vector::contains(&tank.child_objects, id)
    }
} 