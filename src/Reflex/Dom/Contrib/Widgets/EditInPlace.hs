{-# LANGUAGE ConstraintKinds           #-}
{-# LANGUAGE FlexibleContexts          #-}
{-# LANGUAGE LambdaCase                #-}
{-# LANGUAGE MultiWayIf                #-}
{-# LANGUAGE NoMonomorphismRestriction #-}
{-# LANGUAGE OverloadedStrings         #-}
{-# LANGUAGE RankNTypes                #-}
{-# LANGUAGE RecordWildCards           #-}
{-# LANGUAGE RecursiveDo               #-}
{-# LANGUAGE ScopedTypeVariables       #-}
{-# LANGUAGE TemplateHaskell           #-}
{-# LANGUAGE TupleSections             #-}
{-# LANGUAGE TypeFamilies              #-}

module Reflex.Dom.Contrib.Widgets.EditInPlace
  ( editInPlace
  ) where

------------------------------------------------------------------------------
import           Control.Lens hiding ((.=))
import           Control.Monad.Trans
import           Data.Default
import           Data.Map (Map)
import           GHCJS.DOM.Element
import           Reflex
import           Reflex.Dom
import           Reflex.Dom.Contrib.Utils
import           Reflex.Dom.Contrib.Widgets.Common
------------------------------------------------------------------------------


------------------------------------------------------------------------------
data EditState = Viewing
               | Editing
  deriving (Eq,Show,Ord,Enum)


------------------------------------------------------------------------------
-- | Control that can be used in place of dynText whenever you also want that
-- text to be editable in place.
--
-- This control creates a span that either holds text or a text input field
-- allowing that text to be edited.  The edit state is activated by clicking
-- on the text.  Edits are saved when the user presses enter or abandoned if
-- the user presses escape or the text input loses focus.
editInPlace
    :: MonadWidget t m
    => Behavior t Bool
    -- ^ Whether or not click-to-edit is enabled
    -> Dynamic t String
    -- ^ The definitive value of the thing being edited
    -> m (Event t String)
    -- ^ Event that fires when the text is edited
editInPlace active val = do
    rec editState <- holdDyn Viewing $ leftmost
          [ fmapMaybe id $ attachWith
              (\c n -> if c == Editing then Nothing else Just n)
              (current editState) startEditing
          , Viewing <$ sheetEdit
          ]
        cls <- mapDyn mkClass editState
        (e, sheetEdit) <- elDynAttr' "span" cls $ do
          de <- widgetHoldHelper (chooser val) Viewing (updated editState)
          return $ switch $ current de
        let selActive = tag active $ domEvent Click e
        let startEditing = fmapMaybe id $
              (\a -> if a then Just Editing else Nothing) <$> selActive
    return $ fmapMaybe e2maybe sheetEdit


------------------------------------------------------------------------------
mkClass :: EditState -> Map String String
mkClass es = "class" =: (unwords ["editInPlace", ev])
  where
    ev = case es of
           Viewing -> "viewing"
           Editing -> "editing"


------------------------------------------------------------------------------
e2maybe :: SheetEditEvent -> Maybe String
e2maybe EditClose = Nothing
e2maybe (NameChange s) = Just s


------------------------------------------------------------------------------
chooser
    :: MonadWidget t m
    => Dynamic t String
    -> EditState
    -> m (Event t SheetEditEvent)
chooser name Editing = editor name
chooser name Viewing = viewer name


------------------------------------------------------------------------------
data SheetEditEvent = NameChange String
                    | EditClose
  deriving (Read,Show,Eq,Ord)


------------------------------------------------------------------------------
editor
    :: MonadWidget t m
    => Dynamic t String
    -> m (Event t SheetEditEvent)
editor name = do
  pb <- getPostBuild
  (e,w) <- htmlTextInput' "text" $
    def & widgetConfig_setValue .~ tagDyn name pb
  performEvent_ $ ffor pb $ \_ -> do
    liftIO $ elementFocus e
  return $ leftmost
    [ NameChange <$> (tag (current $ value w) $ ffilter (==13) $ _hwidget_keypress w)
    , EditClose <$ ffilter (==27) (_hwidget_keydown w)
    , EditClose <$ ffilter not (updated $ _hwidget_hasFocus w)
    ]


------------------------------------------------------------------------------
viewer
    :: MonadWidget t m
    => Dynamic t String
    -> m (Event t SheetEditEvent)
viewer name = do
  dynText name
  return never
