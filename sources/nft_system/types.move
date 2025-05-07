module swion::nft_system_types {
    use sui::object::{ID};
    use sui::url::{Url};
    use std::string::{String};
    use std::vector;
    
    /// OTW (One Time Witness) for display initialization
    struct NFT_SYSTEM has drop {}

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

    // NFTInfo関連のgetter関数
    public fun get_nft_info_name(info: &NFTInfo): String {
        info.name
    }

    public fun get_nft_info_image(info: &NFTInfo): Url {
        info.image
    }

    public fun get_nft_info_position(info: &NFTInfo): (u64, u64) {
        (info.position_x, info.position_y)
    }

    public fun get_nft_info_id(info: &NFTInfo): ID {
        info.id
    }

    // SynInfo関連のgetter関数
    public fun get_syn_info_id(info: &SynInfo): ID {
        info.id
    }

    public fun get_syn_info_image(info: &SynInfo): Url {
        info.image
    }

    public fun get_syn_info_is_public(info: &SynInfo): bool {
        info.is_public
    }

    public fun get_syn_info_supply(info: &SynInfo): (u64, u64) {
        (info.current_supply, info.max_supply)
    }

    public fun get_syn_info_price(info: &SynInfo): u64 {
        info.price
    }

    public fun get_syn_info_position(info: &SynInfo): (u64, u64) {
        (info.position_x, info.position_y)
    }
    
    // Collection関連のgetter関数
    public fun get_nft_info_from_collection(collection: &NFTCollection, index: u64): &NFTInfo {
        vector::borrow(&collection.nfts, index)
    }

    public fun get_collection_size(collection: &NFTCollection): u64 {
        vector::length(&collection.nfts)
    }
    
    public fun get_syn_info_from_collection(collection: &SynCollection, index: u64): &SynInfo {
        vector::borrow(&collection.syns, index)
    }

    public fun get_syn_collection_size(collection: &SynCollection): u64 {
        vector::length(&collection.syns)
    }

    // NFTInfo作成関数（他モジュールからのアクセス用）
    public fun create_nft_info(id: ID, name: String, image: Url, position_x: u64, position_y: u64): NFTInfo {
        NFTInfo {
            id,
            name,
            image,
            position_x,
            position_y
        }
    }

    // NFTCollection作成関数
    public fun create_nft_collection(nfts: vector<NFTInfo>): NFTCollection {
        NFTCollection { nfts }
    }

    // SynInfo作成関数
    public fun create_syn_info(id: ID, image: Url, is_public: bool, max_supply: u64, current_supply: u64, price: u64, position_x: u64, position_y: u64): SynInfo {
        SynInfo {
            id,
            image,
            is_public,
            max_supply,
            current_supply,
            price,
            position_x,
            position_y
        }
    }

    // SynCollection作成関数
    public fun create_syn_collection(syns: vector<SynInfo>): SynCollection {
        SynCollection { syns }
    }
} 