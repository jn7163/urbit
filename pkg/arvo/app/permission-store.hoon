::  permission-store: data store for keeping track of permissions
::  permissions are white lists or black lists of ships
::
/-  *permission-store
::
|%
+$  move  [bone [%diff diff]]
::
+$  diff
  $%  [%permission-initial =permission-map]
      [%permission-update =permission-update]
  ==
::
+$  state
  $:  permissions=permission-map
  ==
--
::
|_  [bol=bowl:gall %v0 state]
::
++  this  .
::
::  gall interface
::
++  peer-all
  |=  =path
  ^-  (quip move _this)
  ?>  (team:title our.bol src.bol)
  ::  we now proxy all events to this path
  :_  this
  [ost.bol %diff %permission-initial permissions]~
::
++  peer-updates
  |=  =path
  ^-  (quip move _this)
  ?>  (team:title our.bol src.bol)
  ::  we now proxy all events to this path
  [~ this]
::
++  peer-permission
  |=  =path
  ^-  (quip move _this)
  ?~  path  !!
  ?>  (team:title our.bol src.bol)
  ?>  (~(has by permissions) path)
  :_  this
  [ost.bol %diff %permission-update [%create path (~(got by permissions) path)]]~
::
++  peek-x-keys
  |=  pax=path
  ^-  (unit (unit [%noun (set path)]))
  [~ ~ %noun ~(key by permissions)]
::
++  peek-x-permission
  |=  =path
  ^-  (unit (unit [%noun (unit permission)]))
  ?~  path
    ~
  [~ ~ %noun (~(get by permissions) path)]
::
++  peek-x-permitted
  |=  =path
  ^-  (unit (unit [%noun ?]))
  ?~  path
    ~
  =/  pem  (~(get by permissions) t.path)
  ?~  pem
    ~
  =/  who  (slav %p i.path)
  =/  has  (~(has in who.u.pem) who)
  :^  ~  ~  %noun
  ?-(kind.u.pem %black !has, %white has)
::
++  poke-permission-action
  |=  action=permission-action
  ^-  (quip move _this)
  ?>  (team:title our.bol src.bol)
  ?-  -.action
      %add     (handle-add action)
      %remove  (handle-remove action)
      %create  (handle-create action)
      %delete  (handle-delete action)
      %allow   (handle-allow action)
      %deny    (handle-deny action)
  ==
::
++  handle-add
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%add -.act)
  ?~  path.act
    [~ this]
  ::  TODO: calculate diff
  ::  =+  new=(~(dif in who.what.action) who.u.pem)
  ::  ?~(new ~ `what.action(who new))
  ?.  (~(has by permissions) path.act)
    [~ this]
  :-  (send-diff path.act act)
  =/  perm  (~(got by permissions) path.act)
  =.  who.perm  (~(uni in who.perm) who.act)
  this(permissions (~(put by permissions) path.act perm))
::
++  handle-remove
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%remove -.act)
  ?~  path.act
    [~ this]
  ?.  (~(has by permissions) path.act)
    [~ this]
  =/  perm  (~(got by permissions) path.act)
  =.  who.perm  (~(dif in who.perm) who.act)
  ::  TODO: calculate diff
  ::  =+  new=(~(int in who.what.action) who.u.pem)
  ::  ?~(new ~ `what.action(who new))
  :-  (send-diff path.act act)
  this(permissions (~(put by permissions) path.act perm))
::
++  handle-create
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%create -.act)
  ?~  path.act
    [~ this]
  ?:  (~(has by permissions) path.act)
    [~ this]
  :: TODO: calculate diff
  :-  (send-diff path.act act)
  this(permissions (~(put by permissions) path.act permission.act))
::
++  handle-delete
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%delete -.act)
  ?~  path.act
    [~ this]
  ?.  (~(has by permissions) path.act)
    [~ this]
  :-  (send-diff path.act act)
  this(permissions (~(del by permissions) path.act))
::
++  handle-allow
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%allow -.act)
  ?~  path.act
    [~ this]
  =/  perm  (~(get by permissions) path.act)
  ?~  perm
    [~ this]
  ?:  =(kind.u.perm %white)
    (handle-add [%add +.act])
  (handle-remove [%remove +.act])
::
++  handle-deny
  |=  act=permission-action
  ^-  (quip move _this)
  ?>  ?=(%deny -.act)
  ?~  path.act
    [~ this]
  =/  perm  (~(get by permissions) path.act)
  ?~  perm
    [~ this]
  ?:  =(kind.u.perm %black)
    (handle-add [%add +.act])
  (handle-remove [%remove +.act])
::
++  update-subscribers
  |=  [pax=path upd=permission-update]
  ^-  (list move)
  %+  turn  (prey:pubsub:userlib pax bol)
  |=  [=bone *]
  [bone %diff %permission-update upd]
::
++  send-diff
  |=  [pax=path upd=permission-update]
  ^-  (list move)
  %-  zing
  :~  (update-subscribers /all upd)
      (update-subscribers /updates upd)
      (update-subscribers [%permission pax] upd)
  ==
::
--
