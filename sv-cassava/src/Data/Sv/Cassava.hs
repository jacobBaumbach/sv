{-# LANGUAGE OverloadedStrings #-}

{-|
Module      : Data.Sv.Cassava
Copyright   : (C) CSIRO 2017-2018
License     : BSD3
Maintainer  : George Wilson <george.wilson@data61.csiro.au>
Stability   : experimental
Portability : non-portable

This module provides integration between sv and cassava.
It lets you plug cassava's (very fast!) parser into sv's decoding layer.

Our benchmarking indicates that parsing is very expensive,
while decoding is comparatively less performance-sensitive.
So if performance matters to you, and cassava's parser is sufficient for
your needs, you might as well use it!

sv's own parser is much slower than cassava's right now, but aims to have
better error messages and keep more information for you to work with, such as
spacing, quoting, and newline information.
-}

module Data.Sv.Cassava (
  parseDecodeFromCassava
, parseCassava
, decodeFromCassava
) where

import Data.Attoparsec.ByteString (parseOnly)
import Data.ByteString (ByteString)
import Data.ByteString.UTF8 as UTF8
import qualified Data.Csv as Cassava
import qualified Data.Csv.Parser as Cassava
import Data.Sv (toField)
import Data.Sv.Structure.Core (Headedness (..))
import Data.Sv.Decode.Core (Decode', DecodeValidation, validateEitherWith)
import Data.Sv.Decode.Error (badConfig, missingHeader)
import Data.Sv.Decode.Type (NameDecode')
import qualified Data.Sv.Decode.Core as D
import Data.Validation (bindValidation)
import qualified Data.Vector as V

-- | Use an sv 'Decode' to decode from cassava's 'Cassava.Csv' type.
decodeFromCassava :: Decode' ByteString a -> Cassava.Csv -> DecodeValidation ByteString [a]
decodeFromCassava d =
  traverse (D.promote d) . V.toList

decodeNamedFromCassava :: NameDecode' ByteString a -> Cassava.Csv -> DecodeValidation ByteString [a]
decodeNamedFromCassava d c =
  let parts =
    case V.toList c of
      [] -> missingHeader
      (header:body) -> (,body) <$> bindValidation (traverse toField header) (flip makePositional n)
  in bindValidation parts $ \(d,b) ->
     flip bindValidation (decode d) $ traverse (traverse toField) b

-- | Parse a 'Cassava.Csv' from a 'ByteString' using cassava's parser
--
-- This returns its result in a 'DecodeValidation', so that it's compatible
-- with the rest of sv.
parseCassava :: Cassava.DecodeOptions -> ByteString -> DecodeValidation ByteString Cassava.Csv
parseCassava opts =
  validateEitherWith (D.BadParse . UTF8.fromString) . parseOnly (Cassava.csv opts)

-- | Parse a 'Cassava.Csv' from a 'ByteString' using cassava's parser, then
-- decode it using the given 'Decode'.
--
-- This has the benefit of letting you use cassava's parser, which is very fast,
-- with sv's decoding.
parseDecodeFromCassava :: Decode' ByteString a -> Headedness -> Cassava.DecodeOptions -> ByteString -> DecodeValidation ByteString [a]
parseDecodeFromCassava d h opts bs =
  (chompFirst h <$> parseCassava opts bs) `bindValidation` decodeFromCassava d
    where
      -- The csv returned from cassava's parser may include a header row.
      -- If it does, we want to skip that row.
      chompFirst Headed   = V.drop 1
      chompFirst Unheaded = id

parseDecodeNamedFromCassava :: NameDecode' ByteString a -> Headedness -> Cassava.DecodeOptions -> ByteString -> DecodeValidation ByteString [a]
parseDecodeNamedFromCassava d h opts b =
  case h of
    Unheaded -> badConfig "Your config indicates your csv has no header, but a header is required"
    Headed -> bindValidation (parseCassava opts b) (\csv -> decodeNamedFromCassava d csv)
