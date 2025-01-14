{-# LANGUAGE DerivingStrategies #-}
{-# LANGUAGE OverloadedLists #-}

-- | We have a bunch of datatypes, and a single recipe (constructor) for each
-- datatype. This means the wiring can be type-directed: we don't have to make a
-- decision at the term level about which constructor to use.
--
-- We wire the constructors in two ways: manually, and using a bit of dynamic
-- typing magic from the "Cauldron" module.
module Main where

import Cauldron
import Data.Maybe (fromJust)

{-
  HERE ARE A BUNCH OF DATATYPES.

  The idea is that each datatype represents a bean, a component of our application.

  In a real application, these datatypes would be records containing effectful functions.

-}

data A = A deriving (Show)

data B = B deriving (Show)

data C = C deriving (Show)

data D = D deriving (Show)

data E = E deriving (Show)

data F = F deriving (Show)

data G = G deriving (Show)

data H = H deriving (Show)

data I = I deriving (Show)

data J = J deriving (Show)

data K = K deriving (Show)

data L = L deriving (Show)

data M = M deriving (Show)

data N = N deriving (Show)

data O = O deriving (Show)

data P = P deriving (Show)

data Q = Q deriving (Show)

data R = R deriving (Show)

data S = S deriving (Show)

data T = T deriving (Show)

data U = U deriving (Show)

data V = V deriving (Show)

data W = W deriving (Show)

data X = X deriving (Show)

data Y = Y deriving (Show)

data Z = Z deriving (Show)

{-
  These beans are a bit special: they are "secondary" beans which are optionally
  produced by the constructors of other beans.

  They have Monoid instances. The values returned by all the constructors that
  produce them will be combined.
-}

-- | A window into the internal state of some bean.
newtype Inspector = Inspector {inspect :: IO [String]}
  deriving newtype (Semigroup, Monoid)

-- | And initialization action which some beans might register.
newtype Initializer = Initializer {runInitializer :: IO ()}
  deriving newtype (Semigroup, Monoid)

{-
  HERE ARE A BUNCH OF CONSTRUCTORS AND DECORATORS.

-}
makeA :: A
makeA = A

-- A bean with a monoidal registration.
--
-- The registration could be some generic introspection mechanism, or perhaps
-- some effectful action that sets up a worker thread.
makeB :: (Inspector, B)
makeB = (Inspector (pure ["B stuff"]), B)

makeC :: C
makeC = C

makeD :: D
makeD = D

makeE :: A -> E
makeE = \_ -> E

makeF :: B -> C -> (Inspector, F)
makeF = \_ _ -> (Inspector (pure ["F stuff"]), F)

-- | A bean with a self-dependency!
--
-- We need this if we want self-invocations to be decorated.
--
-- Dependency cycles of more than one bean are forbidden, however.
makeG :: E -> F -> G -> G
makeG _ _ _ = G

-- | A decorator.
--
--  Decorators are basically normal constructors, only that they return
--  a Endo that knows how to tweak the value of a bean.
--
-- Because they are normal constructors, they can be effectful, and they
-- might have dependencies of their own.
makeGDeco1 :: A -> G -> G
makeGDeco1 _ g = g

-- | A bean with two monoidal registrations.
makeH :: A -> D -> G -> (Initializer, Inspector, H)
makeH _ _ _ = (Initializer (putStrLn "H init"), Inspector (pure ["H stuff"]), H)

-- | Notice that this bean has "Inspector" as a dependency. Inspector is a
-- monoidal bean which is aggregated across all the constructor that register
-- it. This is OK as long as there are no dependency cycles.
--
-- Why would a bean depend on such a aggregated bean? Well, for example, a
-- server bean might want to publish diagnostic information collected from beans
-- that register it.
makeZ :: Inspector -> D -> H -> Z
makeZ _ _ _ = Z

makeZDeco1 :: B -> E -> Z -> Z
makeZDeco1 _ _ z = z

-- | A decorator with a monoidal registration.
makeZDeco2 :: (F -> Z -> (Initializer, Z))
makeZDeco2 = \_ z -> (Initializer (putStrLn "Z deco init"), z)

data Entrypoint = Entrypoint Initializer Inspector Z

boringWiring :: IO Entrypoint
boringWiring = do
  let -- We have to remember to collect the monoidal registrations.
      initializer = init1 <> init2
      -- We have to remember to collect the monoidal registrations.
      inspector = inspector1 <> inspector2 <> inspector3
      -- Now let's tie the constructors together.
      a = makeA
      (inspector1, b) = makeB
      c = makeC
      d = makeD
      e = makeE a
      (inspector2, f) = makeF b c
      g0 = makeG e f g
      g1 = makeGDeco1 a g0
      g = g1
      -- Here we apply a single decorator.
      (init1, inspector3, h) = makeH a d g
      -- Compose the decorators before applying them.
      z0 = makeZ inspector d h
      z1 = makeZDeco1 b e z0
      (init2, z2) = makeZDeco2 f z1
      z = z2
  pure $ Entrypoint initializer inspector z

-- | Here we don't have to worry about positional parameters. We throw all the
-- constructors into the 'Cauldron' and taste the bean values at the end, plus a
-- graph we may want to draw.
--
-- Note that we detect wiring errors *before* running the effectful constructors.
coolWiring :: Either RecipeError (IO Entrypoint)
coolWiring = fmap (fmap (fromJust . taste @Entrypoint)) $ cook allowSelfDeps cauldron

cauldron :: Cauldron IO
cauldron :: Cauldron IO =
  [ recipe @A $ val $ pure makeA,
    recipe @B $ val $ pure makeB,
    recipe @C $ val $ wire makeC,
    recipe @D $ val $ wire makeD,
    recipe @E $ val $ wire makeE,
    recipe @F $ val $ wire makeF,
    recipe @G $
      Recipe
        { bean = val $ wire makeG,
          decos =
            [ val $ wire makeGDeco1
            ]
        },
    recipe @H $ val $ wire makeH,
    recipe @Z
      Recipe
        { bean = val $ wire makeZ,
          decos =
            [ val $ wire makeZDeco1,
              val $ wire makeZDeco2
            ]
        },
    recipe @Entrypoint $ val $ wire Entrypoint
  ]

main :: IO ()
main = do
  -- "manual" wiring
  do
    Entrypoint (Initializer {runInitializer}) (Inspector {inspect}) z <- boringWiring
    inspection <- inspect
    print inspection
    print z
    runInitializer
  -- wiring with Cauldron
  merr <- case coolWiring of
    Left badBeans -> do
      putStrLn $ prettyRecipeError badBeans
      pure $ Just badBeans
    Right action -> do
      Entrypoint (Initializer {runInitializer}) (Inspector {inspect}) z <- action
      inspection <- inspect
      print inspection
      print z
      runInitializer
      pure $ Nothing
  let depGraph = getDependencyGraph cauldron
  writeAsDot (defaultStyle merr) "beans.dot" depGraph
  writeAsDot (defaultStyle merr) "beans-no-agg.dot" $ removeSecondaryBeans $ depGraph
  writeAsDot (defaultStyle merr) "beans-no-agg-no-decos.dot" $ removeDecos $ removeSecondaryBeans $ depGraph
  writeAsDot (defaultStyle merr) "beans-simple.dot" $ collapseToPrimaryBeans $ removeDecos $ removeSecondaryBeans $ depGraph
  writeAsDot (defaultStyle merr) "beans-simple-with-decos.dot" $ collapseToPrimaryBeans $ removeSecondaryBeans $ depGraph
