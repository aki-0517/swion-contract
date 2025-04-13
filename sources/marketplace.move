module swion::marketplace {
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::kiosk_extension;
    use sui::bag::{Self, Bag};
    use sui::object::{Self, ID, UID};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::transfer;
    use sui::tx_context::{Self, TxContext};
    use sui::dynamic_field as df;
    use sui::event;
    use std::string::{Self, String};
    use std::option::{Self, Option};
    use swion::nft_system::{Self, SynObject};

    // エラーコード
    const ENotEnoughPermissions: u64 = 1;
    const EBidTooLow: u64 = 2;
    const EBidNotFound: u64 = 3;
    const EInvalidBidder: u64 = 4;
    const EBidExpired: u64 = 5;
    const EInvalidPayment: u64 = 6;

    // アプリケーションの権限設定
    const PERMISSIONS: u128 = 3; // place と lock の両方の権限を要求

    /// マーケットプレイス拡張のWitness
    struct MarketplaceExtension has drop {}

    /// Kioskの名前用のキー
    struct KioskName has copy, store, drop {}

    /// 入札情報の構造体
    struct Bid has store, drop {
        bidder: address,
        amount: u64,
        expires_at: u64
    }

    /// コレクション入札情報の構造体
    struct CollectionBid has store, drop {
        bidder: address,
        amount: u64,
        expires_at: u64,
        collection_id: ID
    }

    // イベント
    struct BidPlacedEvent has copy, drop {
        kiosk_id: ID,
        syn_id: ID,
        bidder: address,
        amount: u64
    }

    struct BidAcceptedEvent has copy, drop {
        kiosk_id: ID,
        syn_id: ID,
        bidder: address,
        amount: u64
    }

    struct CollectionBidPlacedEvent has copy, drop {
        kiosk_id: ID,
        collection_id: ID,
        bidder: address,
        amount: u64
    }

    /// マーケットプレイス拡張をKioskに追加
    public fun add(kiosk: &mut Kiosk, cap: &KioskOwnerCap, ctx: &mut TxContext) {
        kiosk_extension::add(MarketplaceExtension {}, kiosk, cap, PERMISSIONS, ctx)
    }

    /// Kioskに名前を設定
    public fun set_name(kiosk: &mut Kiosk, cap: &KioskOwnerCap, name: String) {
        let uid_mut = kiosk::uid_mut_as_owner(kiosk, cap);
        if (df::exists_(uid_mut, KioskName {})) {
            *df::borrow_mut(uid_mut, KioskName {}) = name
        } else {
            df::add(uid_mut, KioskName {}, name)
        }
    }

    /// Kioskの名前を取得
    public fun get_name(kiosk: &Kiosk): Option<String> {
        if (df::exists_(kiosk::uid(kiosk), KioskName {})) {
            option::some(*df::borrow(kiosk::uid(kiosk), KioskName {}))
        } else {
            option::none()
        }
    }

    /// SynObjectに対して入札を行う
    public entry fun place_bid(
        kiosk: &mut Kiosk,
        syn_id: ID,
        payment: &mut Coin<SUI>,
        expires_at: u64,
        ctx: &mut TxContext
    ) {
        assert!(kiosk_extension::can_place<MarketplaceExtension>(kiosk), ENotEnoughPermissions);
        
        let storage = kiosk_extension::storage_mut(MarketplaceExtension {}, kiosk);
        let bid_amount = coin::value(payment);
        
        // 既存の入札があれば、より高い金額のみ受け付ける
        if (bag::contains(storage, syn_id)) {
            let existing_bid = bag::borrow<ID, Bid>(storage, syn_id);
            assert!(bid_amount > existing_bid.amount, EBidTooLow);
        };

        // 新しい入札を保存
        let bid = Bid {
            bidder: tx_context::sender(ctx),
            amount: bid_amount,
            expires_at
        };
        
        bag::add(storage, syn_id, bid);

        // イベントを発行
        event::emit(BidPlacedEvent {
            kiosk_id: object::id(kiosk),
            syn_id,
            bidder: tx_context::sender(ctx),
            amount: bid_amount
        });
    }

    /// コレクション全体に対して入札を行う
    public entry fun place_collection_bid(
        kiosk: &mut Kiosk,
        collection_id: ID,
        payment: &mut Coin<SUI>,
        expires_at: u64,
        ctx: &mut TxContext
    ) {
        assert!(kiosk_extension::can_place<MarketplaceExtension>(kiosk), ENotEnoughPermissions);
        
        let storage = kiosk_extension::storage_mut(MarketplaceExtension {}, kiosk);
        let bid_amount = coin::value(payment);

        let collection_bid = CollectionBid {
            bidder: tx_context::sender(ctx),
            amount: bid_amount,
            expires_at,
            collection_id
        };

        bag::add(storage, collection_id, collection_bid);

        // イベントを発行
        event::emit(CollectionBidPlacedEvent {
            kiosk_id: object::id(kiosk),
            collection_id,
            bidder: tx_context::sender(ctx),
            amount: bid_amount
        });
    }

    /// 入札を受け入れる（Kioskオーナーのみ実行可能）
    public entry fun accept_bid(
        kiosk: &mut Kiosk,
        cap: &KioskOwnerCap,
        syn_id: ID,
        payment: &mut Coin<SUI>,
        ctx: &mut TxContext
    ) {
        let storage = kiosk_extension::storage_mut(MarketplaceExtension {}, kiosk);
        assert!(bag::contains(storage, syn_id), EBidNotFound);

        let Bid { bidder, amount, expires_at } = bag::remove<ID, Bid>(storage, syn_id);
        assert!(tx_context::epoch(ctx) <= expires_at, EBidExpired);
        assert!(coin::value(payment) >= amount, EInvalidPayment);

        // 支払いの処理
        let payment_to_owner = coin::split(payment, amount, ctx);
        transfer::public_transfer(payment_to_owner, kiosk::owner(kiosk));

        // SynObjectの転送
        let syn: SynObject = kiosk::take<SynObject>(kiosk, cap, syn_id);
        transfer::public_transfer<SynObject>(syn, bidder);

        // イベントを発行
        event::emit(BidAcceptedEvent {
            kiosk_id: object::id(kiosk),
            syn_id,
            bidder,
            amount
        });
    }

    /// 入札をキャンセルする（入札者のみ実行可能）
    public entry fun cancel_bid(
        kiosk: &mut Kiosk,
        syn_id: ID,
        ctx: &mut TxContext
    ) {
        let storage = kiosk_extension::storage_mut(MarketplaceExtension {}, kiosk);
        assert!(bag::contains(storage, syn_id), EBidNotFound);

        let bid = bag::borrow<ID, Bid>(storage, syn_id);
        assert!(bid.bidder == tx_context::sender(ctx), EInvalidBidder);

        bag::remove<ID, Bid>(storage, syn_id);
    }

    /// 期限切れの入札を削除する
    public entry fun clean_expired_bids(
        kiosk: &mut Kiosk,
        syn_id: ID,
        ctx: &mut TxContext
    ) {
        let storage = kiosk_extension::storage_mut(MarketplaceExtension {}, kiosk);
        if (bag::contains(storage, syn_id)) {
            let bid = bag::borrow<ID, Bid>(storage, syn_id);
            if (tx_context::epoch(ctx) > bid.expires_at) {
                bag::remove<ID, Bid>(storage, syn_id);
            }
        }
    }
} 

#[test_only]
module swion::marketplace_tests {
    use sui::test_scenario::{Self as ts, Scenario};
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::kiosk::{Self, Kiosk, KioskOwnerCap};
    use sui::transfer;
    use sui::object::{Self, ID};
    use std::string;
    use swion::marketplace::{Self};
    use swion::nft_system::{Self, SynObject};

    // テストアカウント
    const OWNER: address = @0xA;
    const BIDDER: address = @0xB;

    // テスト用のヘルパー関数
    fun setup_test(): Scenario {
        let scenario = ts::begin(OWNER);
        // Kioskの作成
        let ctx = ts::ctx(&mut scenario);
        let (kiosk, cap) = kiosk::new(ctx);
        
        // マーケットプレイス拡張を追加
        marketplace::add(&mut kiosk, &cap, ctx);
        
        // 名前を設定
        marketplace::set_name(&mut kiosk, &cap, string::utf8(b"Test Kiosk"));
        
        // KioskとCapを共有
        transfer::public_share_object(kiosk);
        transfer::public_transfer(cap, OWNER);
        
        scenario
    }

    #[test]
    fun test_place_and_accept_bid() {
        let scenario = setup_test();
        let syn_id: ID;
        
        // NFTを作成してKioskに配置
        ts::next_tx(&mut scenario, OWNER);
        {
            let ctx = ts::ctx(&mut scenario);
            let syn = nft_system::create_test_nft(ctx);
            syn_id = object::id(&syn);
            
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let cap = ts::take_from_sender<KioskOwnerCap>(&scenario);
            
            kiosk::place(&mut kiosk, &cap, syn);
            kiosk::list<SynObject>(&mut kiosk, &cap, syn_id, 1000);
            
            ts::return_shared(kiosk);
            ts::return_to_sender(&scenario, cap);
        };

        // 入札を行う
        ts::next_tx(&mut scenario, BIDDER);
        {
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
            
            marketplace::place_bid(
                &mut kiosk,
                syn_id,
                &mut coin,
                1000,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(kiosk);
            transfer::public_transfer(coin, BIDDER);
        };

        // 入札を受け入れる
        ts::next_tx(&mut scenario, OWNER);
        {
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let cap = ts::take_from_sender<KioskOwnerCap>(&scenario);
            let payment = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
            
            marketplace::accept_bid(
                &mut kiosk,
                &cap,
                syn_id,
                &mut payment,
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(kiosk);
            ts::return_to_sender(&scenario, cap);
            coin::burn_for_testing(payment);
        };

        ts::end(scenario);
    }

    #[test]
    #[expected_failure(abort_code = swion::marketplace::EBidTooLow)]
    fun test_bid_too_low() {
        let scenario = setup_test();
        let syn_id: ID;
        
        // NFTを作成してKioskに配置
        ts::next_tx(&mut scenario, OWNER);
        {
            let ctx = ts::ctx(&mut scenario);
            let syn = nft_system::create_test_nft(ctx);
            syn_id = object::id(&syn);
            
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let cap = ts::take_from_sender<KioskOwnerCap>(&scenario);
            
            kiosk::place(&mut kiosk, &cap, syn);
            kiosk::list<SynObject>(&mut kiosk, &cap, syn_id, 1000);
            
            ts::return_shared(kiosk);
            ts::return_to_sender(&scenario, cap);
        };

        // 最初の入札を行う（1000）
        ts::next_tx(&mut scenario, BIDDER);
        {
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let coin = coin::mint_for_testing<SUI>(1000, ts::ctx(&mut scenario));
            
            marketplace::place_bid(
                &mut kiosk,
                syn_id,
                &mut coin,
                1000, // expires_at
                ts::ctx(&mut scenario)
            );
            
            ts::return_shared(kiosk);
            coin::burn_for_testing(coin);
        };

        // 低額の入札を行う（500）- ここで失敗するはず
        ts::next_tx(&mut scenario, @0xC); // 別の入札者
        {
            let kiosk = ts::take_shared<Kiosk>(&scenario);
            let coin = coin::mint_for_testing<SUI>(500, ts::ctx(&mut scenario));
            
            marketplace::place_bid(
                &mut kiosk,
                syn_id,
                &mut coin,
                1000,
                ts::ctx(&mut scenario)
            ); // ここで EBidTooLow エラーが発生するはず
            
            ts::return_shared(kiosk);
            coin::burn_for_testing(coin);
        };

        ts::end(scenario);
    }

    #[test]
    fun test_cancel_bid() {
        let scenario = setup_test();
        // ... 入札キャンセルのテストケース実装
        ts::end(scenario);
    }
}