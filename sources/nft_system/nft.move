module swion::nft_system_nft {
    use sui::object::{Self, ID, UID};
    use sui::tx_context::{Self, TxContext};
    use sui::transfer;
    use sui::event;
    use sui::url::{Self, Url};
    use std::string::{Self, String};
    use std::vector;

    use swion::nft_system_water_tank::{Self as water_tank, WaterTank};
    use swion::nft_system_types::{NFTInfo, NFTCollection, create_nft_info, create_nft_collection};

    /// 個々のNFT Objectを表す構造体
    struct NFTObject has key, store {
        id: UID,
        owner: address,
        image: Url,
        name: String,
        // NFTObject の配置情報: x軸と y軸
        position_x: u64,
        position_y: u64
    }

    struct MintNFTObjectEvent has copy, drop {
        nft_id: ID,
        owner: address,
        name: String
    }

    struct UpdateObjectPositionEvent has copy, drop {
        nft_id: ID,
        new_x: u64,
        new_y: u64
    }

    struct UpdateNFTInfoEvent has copy, drop {
        nft_id: ID,
        owner: address,
        new_name: String
    }

    /// 個々の NFTObject の mint
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
        assert!(sender == water_tank::get_tank_owner(tank), 1);
        nft.position_x = new_x;
        nft.position_y = new_y;
        event::emit(UpdateObjectPositionEvent {
            nft_id: object::uid_to_inner(&nft.id),
            new_x,
            new_y
        });
    }

    /// ウォータータンクに NFTObject を添付する
    public entry fun attach_object(
        tank: &mut WaterTank,
        nft: &mut NFTObject,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーであることをチェック
        assert!(sender == water_tank::get_tank_owner(tank), 2);
        let nft_id = object::uid_to_inner(&nft.id);
        
        // WaterTankモジュールの関数を使用して追加
        water_tank::add_nft_to_tank(tank, nft_id);
    }

    /// レイアウトを保存（位置更新と添付を同時に行う）
    public entry fun save_layout(
        tank: &mut WaterTank,
        nft: &mut NFTObject,
        new_x: u64,
        new_y: u64,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // タンクのオーナーのみ更新可能
        assert!(sender == water_tank::get_tank_owner(tank), 5);
        
        // NFTの位置を更新
        nft.position_x = new_x;
        nft.position_y = new_y;
        
        // NFTがまだタンクに添付されていない場合は追加
        let nft_id = object::uid_to_inner(&nft.id);
        water_tank::add_nft_to_tank(tank, nft_id);
        
        event::emit(UpdateObjectPositionEvent {
            nft_id,
            new_x,
            new_y
        });
    }

    /// ウォレットアドレスからSBTに紐付いたNFT Objectの情報を全て取得する
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
            
            if (water_tank::contains_object(tank, &nft_id)) {
                let info = create_nft_info(
                    nft_id,
                    nft.name,
                    nft.image,
                    nft.position_x,
                    nft.position_y
                );
                vector::push_back(&mut result, info);
            };
            
            vector::push_back(&mut remaining_nfts, nft);
            i = i + 1;
        };

        vector::destroy_empty(nfts);
        (create_nft_collection(result), remaining_nfts)
    }

    // Getter関数
    public fun get_nft_position(nft: &NFTObject): (u64, u64) {
        (nft.position_x, nft.position_y)
    }

    public fun get_nft_image(nft: &NFTObject): &Url {
        &nft.image
    }

    public fun get_nft_owner(nft: &NFTObject): address {
        nft.owner
    }

    public fun get_nft_name(nft: &NFTObject): &String {
        &nft.name
    }

    public fun get_nft_id(nft: &NFTObject): ID {
        object::uid_to_inner(&nft.id)
    }

    /// NFTObjectのnameとimageを更新する関数
    public entry fun update_nft_info(
        nft: &mut NFTObject,
        new_name: vector<u8>,
        new_image: vector<u8>,
        ctx: &mut TxContext
    ) {
        let sender = tx_context::sender(ctx);
        // オーナーのみが更新可能
        assert!(sender == nft.owner, 3);
        
        // 新しい名前とイメージを設定
        nft.name = string::utf8(new_name);
        nft.image = url::new_unsafe_from_bytes(new_image);
        
        // イベント発行
        event::emit(UpdateNFTInfoEvent {
            nft_id: object::uid_to_inner(&nft.id),
            owner: nft.owner,
            new_name: nft.name
        });
    }
} 