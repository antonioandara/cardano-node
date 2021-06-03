{-# LANGUAGE GADTs #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE NamedFieldPuns #-}
{-# LANGUAGE RankNTypes #-}
{-# LANGUAGE RecordWildCards #-}
{-# LANGUAGE TemplateHaskell #-}

module Test.Cardano.Api.TxBody (tests) where

import           Cardano.Prelude

import           Hedgehog (Property, forAll, property, tripping)
import           Test.Tasty (TestTree)
import           Test.Tasty.Hedgehog (testProperty)
import           Test.Tasty.TH (testGroupGenerator)

import           Cardano.Api

import           Test.Cardano.Api.Typed.Gen (genTxBody, genTxBodyContent)


prop_roundtrip_TxBody_make_get_Byron :: Property
prop_roundtrip_TxBody_make_get_Byron = roundtripTxBodyMakeGet ByronEra

prop_roundtrip_TxBody_make_get_Shelley :: Property
prop_roundtrip_TxBody_make_get_Shelley = roundtripTxBodyMakeGet ShelleyEra

prop_roundtrip_TxBody_make_get_Allegra :: Property
prop_roundtrip_TxBody_make_get_Allegra = roundtripTxBodyMakeGet AllegraEra

prop_roundtrip_TxBody_make_get_Mary :: Property
prop_roundtrip_TxBody_make_get_Mary = roundtripTxBodyMakeGet MaryEra

-- TODO Alonzo
-- prop_roundtrip_TxBody_make_get_Alonzo :: Property
-- prop_roundtrip_TxBody_make_get_Alonzo = roundtripTxBodyMakeGet AlonzoEra


roundtripTxBodyMakeGet :: IsCardanoEra era => CardanoEra era -> Property
roundtripTxBodyMakeGet era =
  property $ do
    content <- forAll $ genTxBodyContent era
    tripping
      (normalizeOriginal $ review content)
      (\_ -> makeTransactionBody content)
      (<&> \(TxBody content') -> normalizeRoundtrip content')


-- * normalize = strip unnecessary details

normalizeOriginal :: TxBodyContent ViewTx era -> TxBodyContent ViewTx era
normalizeOriginal content =
  content
    { txAuxScriptData = TxAuxScriptDataNone
      -- TODO alonzo: this is just stub, remove it
    , txAuxScripts    = normalizeAuxScripts   $ txAuxScripts   content
    , txCertificates  = normalizeCertificates $ txCertificates content
    , txIns           = sortOn fst            $ txIns          content
    , txMetadata      = normalizeMetadata     $ txMetadata     content
    , txMintValue     = normalizeMintValue    $ txMintValue    content
    , txWithdrawals   = normalizeWithdrawals  $ txWithdrawals  content
    }

normalizeRoundtrip :: TxBodyContent ViewTx era -> TxBodyContent ViewTx era
normalizeRoundtrip content@TxBodyContent{txIns} =
  content
    { txAuxScriptData = TxAuxScriptDataNone
      -- TODO alonzo: this is just stub, remove it
    , txIns           = sortOn fst txIns
    }

normalizeMetadata :: TxMetadataInEra era -> TxMetadataInEra era
normalizeMetadata = \case
  TxMetadataInEra _ (TxMetadata m) | null m -> TxMetadataNone
  other                                     -> other

normalizeAuxScripts :: TxAuxScripts era -> TxAuxScripts era
normalizeAuxScripts = \case
  TxAuxScripts _       []      -> TxAuxScriptsNone
  TxAuxScripts support scripts ->
    TxAuxScripts support $ map upgradeScriptInEra scripts
  other -> other

normalizeWithdrawals :: TxWithdrawals ViewTx era -> TxWithdrawals ViewTx era
normalizeWithdrawals = \case
  TxWithdrawals _ [] -> TxWithdrawalsNone
  other              -> other

normalizeCertificates :: TxCertificates ViewTx era -> TxCertificates ViewTx era
normalizeCertificates = \case
  TxCertificates _ [] _ -> TxCertificatesNone
  other                 -> other

normalizeMintValue :: TxMintValue ViewTx era -> TxMintValue ViewTx era
normalizeMintValue = \case
  TxMintValue _ v _ | v == mempty -> TxMintNone
  other                           -> other


upgradeScriptInEra :: ScriptInEra era -> ScriptInEra era
upgradeScriptInEra = \case
  ScriptInEra SimpleScriptV1InAllegra script ->
    ScriptInEra SimpleScriptV2InAllegra $ upgradeScript script
  ScriptInEra SimpleScriptV1InMary script ->
    ScriptInEra SimpleScriptV2InMary $ upgradeScript script
  ScriptInEra SimpleScriptV1InAlonzo script ->
    ScriptInEra SimpleScriptV2InAlonzo $ upgradeScript script
  other -> other

upgradeScript :: Script SimpleScriptV1 -> Script SimpleScriptV2
upgradeScript (SimpleScript SimpleScriptV1 script) =
  SimpleScript SimpleScriptV2 $ upgradeSimpleScript script

upgradeSimpleScript ::
  SimpleScript SimpleScriptV1 -> SimpleScript SimpleScriptV2
upgradeSimpleScript = \case
  RequireSignature hash -> RequireSignature hash
  RequireAllOf scripts  -> RequireAllOf $ map upgradeSimpleScript scripts
  RequireAnyOf scripts  -> RequireAnyOf $ map upgradeSimpleScript scripts
  RequireMOf n scripts  -> RequireMOf n $ map upgradeSimpleScript scripts


review :: TxBodyContent build era -> TxBodyContent ViewTx era
review TxBodyContent{..} =
  TxBodyContent
    { txIns            = map reviewTxIn     txIns
    , txProtocolParams = ViewTx
    , txWithdrawals    = reviewWithdrawals  txWithdrawals
    , txCertificates   = reviewCertificates txCertificates
    , txMintValue      = reviewMintValue    txMintValue
    , ..
    }

reviewTxIn ::
  (TxIn, BuildTxWith build  (Witness WitCtxTxIn era)) ->
  (TxIn, BuildTxWith ViewTx (Witness WitCtxTxIn era))
reviewTxIn = second $ const ViewTx

reviewWithdrawals :: TxWithdrawals build era -> TxWithdrawals ViewTx era
reviewWithdrawals = \case
  TxWithdrawalsNone                 -> TxWithdrawalsNone
  TxWithdrawals support withdrawals ->
    TxWithdrawals
      support
      [(address, amount, ViewTx) | (address, amount, _) <- withdrawals]

reviewCertificates :: TxCertificates build era -> TxCertificates ViewTx era
reviewCertificates = \case
  TxCertificatesNone                    -> TxCertificatesNone
  TxCertificates support certificates _ ->
    TxCertificates support certificates ViewTx

reviewMintValue :: TxMintValue build era -> TxMintValue ViewTx era
reviewMintValue = \case
  TxMintNone                  -> TxMintNone
  TxMintValue support value _ -> TxMintValue support value ViewTx


prop_roundtrip_TxBody_get_make_Byron :: Property
prop_roundtrip_TxBody_get_make_Byron = roundtripTxBodyGetMake ByronEra

prop_roundtrip_TxBody_get_make_Shelley :: Property
prop_roundtrip_TxBody_get_make_Shelley = roundtripTxBodyGetMake ShelleyEra

prop_roundtrip_TxBody_get_make_Allegra :: Property
prop_roundtrip_TxBody_get_make_Allegra = roundtripTxBodyGetMake AllegraEra

prop_roundtrip_TxBody_get_make_Mary :: Property
prop_roundtrip_TxBody_get_make_Mary = roundtripTxBodyGetMake MaryEra

-- TODO Alonzo
-- prop_roundtrip_TxBody_get_make_Alonzo :: Property
-- prop_roundtrip_TxBody_get_make_Alonzo = roundtripTxBodyGetMake AlonzoEra


roundtripTxBodyGetMake :: IsCardanoEra era => CardanoEra era -> Property
roundtripTxBodyGetMake era =
  property $ do
    txbody <- forAll $ genTxBody era
    tripping
      txbody
      (\(TxBody content) -> content)
      (makeTransactionBody . rebuildBodyContent)


rebuildBodyContent :: TxBodyContent build era -> TxBodyContent BuildTx era
rebuildBodyContent TxBodyContent{..} =
  TxBodyContent
    { txCertificates   = rebuildCertificates txCertificates
    , txIns            = map rebuildTxIn     txIns
    , txMintValue      = rebuildMintValue    txMintValue
    , txProtocolParams =
        panic
          "rebuildBodyContent: txProtocolParams is not used yet (TODO alonzo)"
    , txWithdrawals    = rebuildWithdrawals  txWithdrawals
    , ..
    }

rebuildTxIn ::
  (TxIn, BuildTxWith build   (Witness WitCtxTxIn era)) ->
  (TxIn, BuildTxWith BuildTx (Witness WitCtxTxIn era))
rebuildTxIn = second $ const $ BuildTxWith $ KeyWitness KeyWitnessForSpending

rebuildWithdrawals :: TxWithdrawals build era -> TxWithdrawals BuildTx era
rebuildWithdrawals = \case
  TxWithdrawalsNone                 -> TxWithdrawalsNone
  TxWithdrawals support withdrawals ->
    TxWithdrawals
      support
      [ ( address
        , amount
        , panic "rebuildWithdrawals: build field should not be checked"
        )
      | (address, amount, _) <- withdrawals
      ]

rebuildCertificates :: TxCertificates build era -> TxCertificates BuildTx era
rebuildCertificates = \case
  TxCertificatesNone                    -> TxCertificatesNone
  TxCertificates support certificates _ ->
    TxCertificates
      support
      certificates
      (panic "rebuildCertificates: build field should not be checked")

rebuildMintValue :: TxMintValue build era -> TxMintValue BuildTx era
rebuildMintValue = \case
  TxMintNone                  -> TxMintNone
  TxMintValue support value _ -> TxMintValue support value $ BuildTxWith mempty


tests :: TestTree
tests = $testGroupGenerator
