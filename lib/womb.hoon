::                                                      ::  ::
::::  /hoon/womb/lib                                    ::  ::
  ::                                                    ::  ::
/?    310                                               ::  version
/+    talk
::                                                      ::  ::
::::                                                    ::  ::
  ::                                                    ::  ::
|%
++  foil                                                ::  ship allocation map
  |*  mold                                              ::  entry mold
  $:  min/@p                                            ::  minimum entry
      ctr/@p                                            ::  next allocated
      und/(set @p)                                      ::  free under counter
      ove/(set @p)                                      ::  alloc over counter
      max/@p                                            ::  maximum entry
      box/(map @p +<)                                   ::  entries
  ==                                                    ::
--                                                      ::
::   $:  min/@p
::       mid/@p
::       max/@p
::       box/(map @p (each mail ))
::   ==
  
:: |%
:: ++  ships  (list {min/@p mid/@p max/@p ish/(map @p state)})
:: ++  state  ?($given $split {$~ mail})

  
:: ++  
|%                                                      ::
++  managed                                             ::  managed plot
  |*  mold                                              ::  
  %-  unit                                              ::  unsplit
  %+  each  +<                                          ::  subdivided
  mail                                                  ::  delivered
::                                                      ::
++  divided
  |*  (managed)
  ?-  +<
    $~      ~
    {$~ $| *}  ~
    {$~ $& *}  (some p.u.+<)
  ==
::
++  moon  (managed _!!)                                 ::  undivided moon
::
++  planet                                              ::  subdivided planet
  (managed (lone (foil moon)))                          ::
::                                                      ::
++  star                                                ::  subdivided star
  (managed (pair (foil moon) (foil planet)))            ::
::                                                      ::
++  galaxy                                              ::  subdivided galaxy
  (managed (trel (foil moon) (foil planet) (foil star)))::
::                                                      ::
:: ++  new-office
::   $:  galaxies/(map ship state)
::       planets/(map ship state)
::       stars/(map ship state)
::   ==
:: ++  state

++  passcode  @pG                                       ::  64-bit passcode
++  mail  @ta                                           ::  email address
++  balance                                             ::  invitation balance
  $:  planets/@ud                                       ::  planet count
      stars/@ud                                         ::  star count
      owner/mail                                        ::  owner's email
      history/(list mail)                               ::  transfer history
  ==                                                    ::
++  client                                              ::  per email
  $:  sta/@ud                                           ::  unused star refs
      has/(set @p)                                      ::  planets owned
  ==                                                    ::
++  property                                            ::  subdivided plots
  $:  galaxies/(map @p galaxy)                          ::  galaxy
      planets/(map @p planet)                           ::  star
      stars/(map @p star)                               ::  planet
  ==                                                    ::
++  invite                                              ::
  $:  who/mail                                          ::  who to send to
      pla/@ud                                           ::  planets to send
      sta/@ud                                           ::  stars to send
      wel/welcome                                       ::  welcome message
  ==                                                    ::
++  welcome                                             ::  welcome message
  $:  intro/tape                                        ::  in invite email
      hello/tape                                        ::  as talk message
  ==                                                    ::
++  reference                                           ::  affiliate credit
  (unit (each @p mail))                                 ::  ship or email
--                                                      ::
::                                                      ::  ::
::::                                                    ::  ::
  ::                                                    ::  ::
|%
++  womb-part  {$womb $0 womb-pith}                     ::  womb state
++  womb-pith                                           ::  womb content
  $:  boss/(unit @p)                                    ::  outside master
      bureau/(map passcode balance)                     ::  active invitations
      office/property                                   ::  properties managed
      hotel/(map mail client)                           ::  everyone we know
  ==                                                    ::
--                                                      ::
::                                                      ::  ::
::::                                                    ::  ::
  ::                                                    ::  ::
|%                                                      ::  arvo structures
++  card                                                ::
  $%  {$flog wire flog}                                 ::
      ::{$wait $~}
      :: {$poke
      {$next p/ring}                                    ::  update private key
      {$tick p/@pG q/@p}                                ::  save ticket
  ==                                                    ::
++  move  (pair bone card)                              ::  user-level move
--
|%
++  murn-by
  |*  {a/(map) b/$-(* (unit))}
  ^-  ?~(a !! (map _p.n.a _(need (b q.n.a))))
  %-  malt
  %+  murn  (~(tap by a))
  ?~  a  $~
  |=  _c=n.a  ^-  (unit _[p.n.a (need (b q.n.a))])
  =+  d=(b q.c)
  ?~(d ~ (some [p.c u.d]))
::
++  unsplit
  |=  a/(map ship (managed))  ^-  (list {ship *})
  %+  skim  (~(tap by a))
  |=({@ a/(managed)} ?=($~ a))
::
++  issuing
  |*  a/(map ship (managed))
  ^-  (list _(need (divided *~(got by a))))
  (turn (sort (~(tap by (murn-by a divided))) lor) tail)
::
::++  grand-map  (map @p czar/(map @p king/(map @p duke/(map @p (set @p)))))
::++  deep-uni-by
::
++  cursor  (pair (unit ship) @u)
::  Create new foil, with parent as a certain size
++  fo-init
  |=  {who/@p syz/bloq}  ::  ^-  (foil *)
  =+  :-  min=(add who (bex syz))
      max=(add who (sub (bex (mul 2 syz)) (bex syz)))
  [min ctr=min und=~ ove=~ max box=~]
::
++  fo
  |_  (foil)
  ++  get                                             ::  nth
    |=  a/@u  ^-  cursor
    ?:  (lth a ~(wyt in und))
      =+  out=(snag a (sort (~(tap in und)) lth))
      [(some out) 0]
    =.  a  (sub a ~(wyt in und))
    |-  ^-  {(unit @p) @u}
    ?:  =(ctr +(max))  [~ a]
    ?:  =(0 a)  [(some ctr) a]
    $(a (dec a), +<.get new)
  ::
  +-  fin  +<                                         ::  abet
  ++  new                                             ::  alloc
    ?:  =(ctr +(max))  +<
    =.  ctr  +(ctr)
    ?.  (~(has in ove) ctr)  +<
    new(ove (~(del in ove) ctr))
  ::
  +-  put
    |*  {a/@p b/*}  ^+  fin           ::  b/_(~(got by box))
    ?>  (fit a)
    =;  adj  adj(box (~(put by box) a b))
    ?:  (~(has in box) a)  fin
    ?:  =(ctr a)  new 
    ?:  (lth a ctr)
      ?.  (~(has in und) a)  fin
      fin(und (~(del in und) a))
    ?.  =(a ctr:new)    :: heuristic
      fin(ove (~(put in ove) a))
    =+  n=new(+< new)
    n(und (~(put in und.n) ctr))
  ::
  ++  fit  |=(a/@p &((lte min a) (lte a max)))        ::  in range
  ++  gud                                             ::  invariant
    ?&  (fit(max +(max)) ctr)
        (~(all in und) fit(max ctr))
        (~(all in ove) fit(min ctr))
        (~(all in box) |=({a/@p *} (fit a)))
        |-  ^-  ?
        ?:  =(min max)  &
        =-  &(- $(min +(min)))
        %+  gte  1              ::  at most one of
        ;:  add
          ?:(=(min ctr) 1 0)
          ?:((~(has in und) min) 1 0)
          ?:((~(has in ove) min) 1 0)
          ?:((~(has by box) min) 1 0)
        ==
    ==
  --
--
::                                                    ::  ::
::::                                                  ::  ::
  !:                                                  ::  ::
|=  {bowl womb-part}                                  ::  main womb work
|_  moz/(list move)
++  abet                                              ::  resolve
  ^-  (quip move *womb-part)
  [(flop moz) +>+<+]
::
++  emit  |=(card %_(+> moz [[ost +<] moz]))          ::  return card
++  emil                                              ::  return cards
  |=  (list card) 
  ^+  +>
  ?~(+< +> $(+< t.+<, +> (emit i.+<)))
::
:: ++  huge-set
::   ^-  (map @p ?($xeno $free $divd))
  
  
:: ++  to-grand-map                                         ::  XX state format?
::   ^-  grand-map
::   =+  ofc=invert-office
::   ;:  deep-uni-by
:: ::
:: ++  from-grand-map
::   |=  a/grand-map
::   ^+  office
  
::
++  take-n
  |=  {{index/@u count/@u} get/$-(@u cursor)}
  ^-  (list ship)
  ?~  count  ~
  %+  biff  p:(get index)
  |=  a/ship  ^-  (list ship)
  [a ^$(index +(index), count (dec count))]
::
++  available
  |=  all/(map ship (managed))  ^-  $-(@u cursor)
  =+  pur=(sort (turn (unsplit all) head) lth)
  =+  len=(lent pur)
  |=(a/@u ?:((gte a len) [~ (sub a len)] [(some (snag a pur)) a]))
::
++  shop-galaxies  (available galaxies.office)
::
::  Stars can be either whole or children of galaxies
++  shop-stars
  |=  nth/@u  ^-  cursor
  =^  out  nth  %.(nth (available stars.office))
  ?^  out  [out nth]
  (shop-star nth (issuing galaxies.office))
::
++  shop-star
  |=  {nth/@u lax/(list {* * r/(foil star)})}  ^-  cursor
  ?~  lax  [~ nth]
  =^  out  nth  (~(get fo r.i.lax) nth)
  ?^  out  [out nth]
  $(lax t.lax)
::
++  shop-planets
  |=  nth/@u  ^-  cursor
  =^  out  nth  %.(nth (available planets.office))
  ?^  out  [out nth]
  =^  out  nth  (shop-planet nth (issuing stars.office))
  ?^  out  [out nth]
  (shop-planet-gal nth (issuing galaxies.office))
::
++  shop-planet
  |=  {nth/@u sat/(list {* q/(foil planet)})}  ^-  cursor
  ?~  sat  [~ nth]
  =^  out  nth  (~(get fo q.i.sat) nth)
  ?^  out  [out nth]
  $(sat t.sat)
::
++  shop-planet-gal
  |=  {nth/@u lax/(list {* * r/(foil star)})}  ^-  cursor
  ?~  lax  [~ nth]
  =^  out  nth  (shop-planet nth (issuing box.r.i.lax))
  ?^  out  [out nth]
  $(lax t.lax)
::
++  peek-x-shop
  |=  tyl/path  ^-  (unit (unit {$ships (list @p)}))
  =;  res  (some (some [%ships res]))
  =+  ~|(bad-path+tyl (raid tyl typ=%tas nth=%ud ~))
  :: =.  nth  (mul 3 nth)
  ?+  typ  ~|(bad-type+typ !!)
    $galaxy  (take-n [nth 3] shop-galaxies)
    $planet  (take-n [nth 3] shop-planets)
    $star    (take-n [nth 3] shop-stars)
  ==
::
++  stats-ship
  |=  who/@p  ^-  (unit (unit (cask _!!)))
  ~
::
++  peek-x-stats
  |=  tyl/path
  ?^  tyl
    (stats-ship ~|(bad-path+tyl (raid tyl who=%p ~)))
  ^-  (unit (unit (cask _!!)))
  ~
::
++  peek-x-invite
  |=  tyl/path  ^-  (unit (unit {$womb-balance balance}))
  =+  ~|(bad-path+tyl (raid tyl pas=%p ~))
  %-  some
  %+  bind  (~(get by bureau) pas)
  |=(bal/balance [%womb-balance bal])
::
++  peek
  |=  {ren/@tas tyl/path}
::  ^-  (unit (unit (pair mark *)))
  ?.  =(ren %x)  ~
  ?~  tyl  ~
  ?+  -.tyl  ~
  ::  /shop/planet/@ud   (list @p)    up to 3 planets
  ::  /shop/star/@ud     (list @p)    up to 3 stars
  ::  /shop/galaxy/@ud   (list @p)    up to 3 galaxies 
    $shop  (peek-x-shop +.tyl)
  ::  /stats                          general stats dump
  ::  /stats/@p                       what we know about @p
    $stats  (peek-x-stats +.tyl)
  ::  /invite/passcode                invitation status  
    $invite  (peek-x-invite +.tyl)
  ==
::
++  poke-invite                                       ::  create invitation
  |=  {ref/reference inv/invite}
  =<  abet
  ?>  |(=(our src) =([~ src] boss))                   ::  me or boss
  .
::
++  poke-obey                                         ::  set/reset boss
  |=  who/(unit @p)
  =<  abet
  ?>  =(our src)                                      ::  me only
  .
::
++  poke-rekey                                        ::  extend will
  |=  $~
  =<  abet
  ?>  |(=(our src) =([~ src] boss))                   ::  privileged
  .
::
++  poke-report                                       ::  report will
  |=  {her/@p wyl/will}                               ::
  =<  abet
  ?>  =(src src)                                      ::  self-authenticated
  .
::
++  poke-claim                                        ::  claim plot, send ticket
  |=  {aut/@uvH her/@p}                               ::
  =<  abet
  ?>  =(src src)
  .
::
++  poke-release                                      ::  release to subdivide
  |=  {gal/@ud sta/@ud}                               ::
  =<  abet  ^+  +>
  ?>  =(our src)                                      ::  privileged
  =.  +>
    ?~  gal  +>
    =+  all=(take-n [0 gal] shop-galaxies)
    ?.  (gth gal (lent all))
      (roll all release-galaxy)
    ~|(too-few-galaxies+[want=gal has=(lent all)] !!)
  ^+  +>
  ?~  sta  +>
  =+  all=(take-n [0 sta] shop-stars)
  ~&  got-stars+all
  ?.  (gth sta (lent all))
    (roll all release-star)
  ~|(too-few-stars+[want=sta has=(lent all)] !!)
::
++  release-galaxy
  =+  [who=*@p res=.]
  |.  ^+  res
  =+  new=(some %& (fo-init who 32) (fo-init who 16) (fo-init who 8))
  =+  gal=(~(got by galaxies.office.res) who)
  ?^  gal  ~|(already-used+who !!)
  res(galaxies.office (~(put by galaxies.office.res) who new))
::
++  release-star
  =+  [who=*@p res=.]
  |.  ^+  res
  ~&  release+who
  =+  new=(some %& (fo-init who 32) (fo-init who 16))
  ?:  (~(has by stars.office.res) who)
    =+  sta=(~(got by stars.office.res) who)
    ?~  sta
      res(stars.office (~(put by stars.office.res) who new))
    ~|(already-used+[who u.sta] !!)
  =+  gal=(~(got by galaxies.office.res) (sein who))
  =;  lax/galaxy
    res(galaxies.office (~(put by galaxies.office.res) (sein who) lax))
  ?.  ?=({$~ $& *} gal)
    ~|(unavailable-galaxy+(sein who) !!)
  %_  gal
      r.p.u
    =+  sta=r.p.u.gal  ^+  sta
    =+  ole=(~(get by box.sta) who)
    ?~  ole  (~(put fo sta) who new)
    ?~  u.ole  (~(put fo sta) who new)
    ~|(already-used+[(sein who) who u.ole] !!)
  ==
::
++  poke-reinvite                                     ::  split invitation
  |=  $:  aut/@uvH                                    ::  hash w/passcode
          inv/invite                                  ::  further invite
      ==
  ?>  =(src src)                                      ::
  =<  abet
  .
--
