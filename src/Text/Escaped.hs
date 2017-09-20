{-# LANGUAGE MultiParamTypeClasses #-}
{-# LANGUAGE FunctionalDependencies #-}
{-# LANGUAGE FlexibleInstances #-}

-- | Chunks of text separated by escape sequences
module Text.Escaped (
  Escaped
  , HasEscaped (escaped, escapeList)
  , Escape
  , Escaped'
  , noEscape
  , escapeNel
) where

import Control.Lens       (Lens', iso)
import Data.Bifoldable    (Bifoldable (bifoldMap))
import Data.Bifunctor     (Bifunctor (bimap))
import Data.Bitraversable (Bitraversable (bitraverse))
import Data.Foldable      (Foldable (foldMap))
import Data.Functor       (Functor (fmap))
import Data.List.NonEmpty (NonEmpty ((:|)))
import Data.Monoid        (Monoid (mappend, mempty))
import Data.Semigroup     (Semigroup ((<>)))
import Data.Traversable   (Traversable (traverse))

-- | 'Escaped e a' is a list of characters separated by escape sequences.
--
-- @a@ can happily be 'Char', but you could just as easily use 'Text' to make
-- sure tricky characters work properly.
--
-- @e@ is the escape sequence, which should be represented by a bespoke sum
-- type rather than something like 'Text'.
--
-- The 'bifoldMap' is particularly useful for this type, as it can turn the
-- whole thing back into a single textual value.
newtype Escaped e a =
  Escaped { _escapeList :: [Either e a]}
  deriving (Eq, Ord, Show)

class HasEscaped c e a | c -> e a where
  escaped :: Lens' c (Escaped e a)
  escapeList :: Lens' c [Either e a]
  {-# INLINE escapeList #-}
  escapeList = escaped . escapeList

instance HasEscaped (Escaped e a) e a where
  {-# INLINE escapeList #-}
  escaped = id
  escapeList = iso _escapeList Escaped

instance Semigroup (Escaped e a) where
  Escaped x <> Escaped y = Escaped (x <> y)

instance Monoid (Escaped e a) where
  mappend = (<>)
  mempty = Escaped mempty

instance Functor (Escaped e) where
  fmap = bimap id

instance Foldable (Escaped e) where
  foldMap = bifoldMap (const mempty)

instance Traversable (Escaped e) where
  traverse = bitraverse pure

instance Bifunctor Escaped where
  bimap f g = Escaped . fmap (bimap f g) . _escapeList

instance Bifoldable Escaped where
  bifoldMap f g = foldMap (bifoldMap f g) . _escapeList

instance Bitraversable Escaped where
  bitraverse f g = fmap Escaped . traverse (bitraverse f g) . _escapeList

-- | 'Escaped'' is for text which only has one valid escape sequence
--
-- This representation only works when there is one escape
-- sequence, as it does not contain any information about which escape sequence
-- occured. The @Escaped@ type is used directly for that purpose.
type Escaped' = Escaped Escape

-- | noEscape is a dramatically-named singleton constructor for Escaped.
noEscape :: a -> Escaped' a
noEscape = Escaped . pure . pure

-- | Put escape sequences in between the elements of a non-empty list.
escapeNel :: NonEmpty a -> Escaped' a
escapeNel as = case as of
  (a :|   []) -> noEscape a
  (a :| x:xs) -> Escaped $ Right a : Left Escape : _escapeList (escapeNel (x:|xs))

-- | A trivial type to be our sole escape sequence. The actual value of the escape is
-- determined externally.
data Escape =
  Escape
  deriving (Eq, Ord, Show)

instance Semigroup Escape where
  Escape <> Escape = Escape

instance Monoid Escape where
  mappend = (<>)
  mempty = Escape
