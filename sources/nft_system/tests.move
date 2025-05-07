#[test_only]
module swion::nft_system_tests {
    use swion::nft_system_water_tank::{
        WaterTank, initialize_tank, update_tank_background,
        update_tank_level
    };
    use swion::nft_system_nft::{
        Self as nft, NFTObject, mint_nft_object, update_object_position,
        attach_object, save_layout
    };
    use swion::nft_system_syn_object::{
        Self as syn_object, SynObject, mint_syn_object, attach_syn_object,
        update_syn_position, get_syn_position
    };
    
    use sui::test_scenario as ts;
    use sui::object;
    use std::vector;

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
            let (_collection, returned_nfts) = nft::get_wallet_nft_collection(&tank, nfts);
            
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
            let (_collection, returned_syns) = syn_object::get_wallet_syn_collection(&tank, syns);
            
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
            let (x, y) = get_syn_position(&syn);
            assert!(x == 150 && y == 300, 300);

            ts::return_to_address(addr1, tank);
            ts::return_to_address(addr1, syn);
        };

        ts::end(scenario);
    }
} 