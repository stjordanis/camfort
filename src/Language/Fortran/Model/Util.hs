
{-|

Miscellaneous combinators.

-}
module Language.Fortran.Model.Util where

import           Control.Applicative
import           Control.Monad.Reader

import           Data.Function       ((&), on)

--------------------------------------------------------------------------------
--  Combinators
--------------------------------------------------------------------------------

-- | Like 'on', but apply a different function to each argument (which are
-- allowed to have different types).
on2 :: (c -> d -> e) -> (a -> c) -> (b -> d) -> a -> b -> e
on2 h g f = (h . g) *.. f


-- | '..*' in the Kleisli category.
matchingWithBoth :: (Monad m) => (a -> b -> m c) -> (c -> m r) -> a -> b -> m r
matchingWithBoth f k = (>>= k) ..* f


-- | 'on2' in the Kleisli category.
matchingWith2 :: (Monad m) => (a -> m a') -> (b -> m b') -> ((a', b') -> m r) -> a -> b -> m r
matchingWith2 = matchingWithBoth ..* on2 (liftA2 (,))


-- | Alternative @('<|>')@ over single-argument functions.
altf :: (Alternative f) => (a -> f b) -> (a -> f b) -> a -> f b
altf = runReaderT ..* (<|>) `on` ReaderT


-- | Alternative @('<|>')@ over two-argument functions.
altf2 :: (Alternative f) => (a -> b -> f c) -> (a -> b -> f c) -> a -> b -> f c
altf2 = curry ..* altf `on` uncurry

-- | Flipped 'fmap'.
(<$$>) :: (Functor f) => f a -> (a -> b) -> f b
(<$$>) = flip (<$>)

-- | Flipped function application.
with :: a -> (a -> b) -> b
with = (&)

-- | @(f *.. g) x y = f x (g y)@. Mnemonic: the @*@ is next to the function
-- which has two arguments.
(*..) :: (a -> c -> d) -> (b -> c) -> a -> b -> d
(f *.. g) x y = f x (g y)

-- | @(f ..* g) x y = f (g x y)@. Mnemonic: the @*@ is next to the function
-- which has two arguments.
(..*) :: (c -> d) -> (a -> b -> c) -> a -> b -> d
f ..* g = curry (f . uncurry g)
