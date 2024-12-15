{-# LANGUAGE BlockArguments #-}
{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE DerivingVia #-}
{-# LANGUAGE DuplicateRecordFields #-}
{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE NoFieldSelectors #-}

module Main (main) where

import Cauldron
import Cauldron.Managed
import Data.Function ((&))
import Data.IORef
import Data.Maybe (fromJust)
import Data.Text (Text)
import Test.Tasty
import Test.Tasty.HUnit

newtype Logger m = Logger
  { logMessage :: Text -> m ()
  }

makeLogger :: IORef [Text] -> forall r. (Logger IO -> IO r) -> IO r
makeLogger ref =
  makeWithWrapperWithMessage
    ref
    "allocating logger"
    "deallocating logger"
    ( Logger \message ->
        modifyIORef ref (++ [message])
    )

data Weird m = Weird
  { weirdOp :: m (),
    anotherWeirdOp :: m ()
  }

makeSelfInvokingWeird :: IORef [Text] -> Logger IO -> Weird IO -> forall r. (Weird IO -> IO r) -> IO r
makeSelfInvokingWeird ref Logger {logMessage} ~Weird {weirdOp = selfWeirdOp} = do
  makeWithWrapperWithMessage
    ref
    "allocating weird"
    "deallocating weird"
    ( Weird
        { weirdOp = do
            modifyIORef ref (++ ["weirdOp 2"])
            logMessage "logging",
          anotherWeirdOp = do
            modifyIORef ref (++ ["another weirdOp 2"])
            selfWeirdOp
        }
    )

makeWeirdDecorator :: Logger IO -> Weird IO -> Weird IO
makeWeirdDecorator Logger {logMessage} Weird {weirdOp = selfWeirdOp, anotherWeirdOp} =
  Weird
    { weirdOp = do
        selfWeirdOp
        logMessage "logging from deco",
      anotherWeirdOp
    }

makeWithWrapperWithMessage ::
  IORef [Text] ->
  Text ->
  Text ->
  a ->
  forall r. (a -> IO r) -> IO r
makeWithWrapperWithMessage ref inMsg outMsg v handler = do
  modifyIORef ref (++ [inMsg])
  r <- handler v
  modifyIORef ref (++ [outMsg])
  pure r

managedCauldron :: IORef [Text] -> Cauldron Managed
managedCauldron ref =
  fromSomeRecipeList
    [ someRecipe @(Logger IO) $ effectfulConstructor do fillArgs do managed (makeLogger ref),
      someRecipe @(Weird IO)
        Recipe
          { bean = effectfulConstructor do
              fillArgs \logger self -> managed (makeSelfInvokingWeird ref logger self),
            decos =
              [ constructor do fillArgs makeWeirdDecorator
              ]
          },
      someRecipe @(Logger IO, Weird IO) $ constructor do fillArgs (,)
    ]

tests :: TestTree
tests =
  testGroup
    "All"
    [ testCase "simple" do
        ref <- newIORef []
        case cook allowSelfDeps (managedCauldron ref) of
          Left _ -> assertFailure "could not wire"
          Right (_, beansAction) -> with beansAction \boiledBeans -> do
            let (Logger {logMessage}, (Weird {anotherWeirdOp}) :: Weird IO) = fromJust . taste $ boiledBeans
            logMessage "foo"
            anotherWeirdOp
            pure ()
        traces <- readIORef ref
        assertEqual
          "traces"
          ["allocating logger", "allocating weird", "foo", "another weirdOp 2", "weirdOp 2", "logging", "logging from deco", "deallocating weird", "deallocating logger"]
          traces
    ]

main :: IO ()
main = defaultMain tests
