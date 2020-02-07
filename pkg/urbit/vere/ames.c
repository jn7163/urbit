/* vere/ames.c
**
*/
#include <fcntl.h>
#include <sys/ioctl.h>
#include <sys/stat.h>
#include <sys/socket.h>
#include <netinet/in.h>
#include <netdb.h>
#include <uv.h>
#include <errno.h>
#include <ncurses/curses.h>
#include <termios.h>
#include <ncurses/term.h>

#include "all.h"
#include "vere/vere.h"

/* _ames_alloc(): libuv buffer allocator.
*/
static void
_ames_alloc(uv_handle_t* had_u,
            size_t len_i,
            uv_buf_t* buf
            )
{
  //  we allocate 2K, which gives us plenty of space
  //  for a single ames packet (max size 1060 bytes)
  //
  void* ptr_v = c3_malloc(2048);
  *buf = uv_buf_init(ptr_v, 2048);
}

/* _ames_pact_free(): free packet struct.
*/
static void
_ames_pact_free(u3_pact* pac_u)
{
  c3_free(pac_u->hun_y);
  c3_free(pac_u->dns_c);
  c3_free(pac_u);
}

/* _ames_send_cb(): send callback.
*/
static void
_ames_send_cb(uv_udp_send_t* req_u, c3_i sas_i)
{
  u3_pact* pac_u = (u3_pact*)req_u;

#if 0
  if ( 0 != sas_i ) {
    u3l_log("ames: send_cb: %s\n", uv_strerror(sas_i));
  }
#endif

  _ames_pact_free(pac_u);
}

/* _ames_send(): send buffer to address on port.
*/
static void
_ames_send(u3_pact* pac_u)
{
  // XX revisit
  u3_pier* pir_u = u3_pier_stub();
  u3_ames* sam_u = pir_u->sam_u;

  if ( !pac_u->hun_y ) {
    _ames_pact_free(pac_u);
    return;
  }

  struct sockaddr_in add_u;

  memset(&add_u, 0, sizeof(add_u));
  add_u.sin_family = AF_INET;
  add_u.sin_addr.s_addr = htonl(pac_u->pip_w);
  add_u.sin_port = htons(pac_u->por_s);

  uv_buf_t buf_u = uv_buf_init((c3_c*)pac_u->hun_y, pac_u->len_w);
  c3_i sas_i;

  if ( 0 != (sas_i = uv_udp_send(&pac_u->snd_u,
                                 &sam_u->wax_u,
                                 &buf_u, 1,
                                 (const struct sockaddr*)&add_u,
                                 _ames_send_cb)) ) {
    u3l_log("ames: send: %s\n", uv_strerror(sas_i));
  }
}

/* _ames_czar_port(): udp port for galaxy.
*/
static c3_s
_ames_czar_port(c3_y imp_y)
{
  if ( c3n == u3_Host.ops_u.net ) {
    return 31337 + imp_y;
  }
  else {
    return 13337 + imp_y;
  }
}

/* _ames_czar_gone(): galaxy address resolution failed.
*/
static void
_ames_czar_gone(u3_pact* pac_u, time_t now)
{
  // XX revisit
  u3_pier* pir_u = u3_pier_stub();
  u3_ames* sam_u = pir_u->sam_u;

  if ( c3y == sam_u->imp_o[pac_u->imp_y] ) {
    u3l_log("ames: czar at %s: not found (b)\n", pac_u->dns_c);
    sam_u->imp_o[pac_u->imp_y] = c3n;
  }

  if ( (0 == sam_u->imp_w[pac_u->imp_y]) ||
       (0xffffffff == sam_u->imp_w[pac_u->imp_y]) )
  {
    sam_u->imp_w[pac_u->imp_y] = 0xffffffff;
  }

  //  keep existing ip for 5 more minutes
  //
  sam_u->imp_t[pac_u->imp_y] = now;

  _ames_pact_free(pac_u);
}

/* _ames_czar_cb(): galaxy address resolution callback.
*/
static void
_ames_czar_cb(uv_getaddrinfo_t* adr_u,
              c3_i              sas_i,
              struct addrinfo*  aif_u)
{
  // XX revisit
  u3_pier* pir_u = u3_pier_stub();
  u3_ames* sam_u = pir_u->sam_u;

  u3_pact* pac_u = (u3_pact*)adr_u->data;
  time_t     now = time(0);

  struct addrinfo* rai_u = aif_u;

  while ( 1 ) {
    if ( !rai_u ) {
      _ames_czar_gone(pac_u, now);
      break;
    }

    if ( (AF_INET == rai_u->ai_family) ) {
      struct sockaddr_in* add_u = (struct sockaddr_in *)rai_u->ai_addr;
      c3_w old_w = sam_u->imp_w[pac_u->imp_y];

      sam_u->imp_w[pac_u->imp_y] = ntohl(add_u->sin_addr.s_addr);
      sam_u->imp_t[pac_u->imp_y] = now;
      sam_u->imp_o[pac_u->imp_y] = c3y;

#if 1
      if ( sam_u->imp_w[pac_u->imp_y] != old_w
        && sam_u->imp_w[pac_u->imp_y] != 0xffffffff ) {
        u3_noun wad = u3i_words(1, &sam_u->imp_w[pac_u->imp_y]);
        u3_noun nam = u3dc("scot", c3__if, wad);
        c3_c*   nam_c = u3r_string(nam);

        u3l_log("ames: czar %s: ip %s\n", pac_u->dns_c, nam_c);

        c3_free(nam_c); u3z(nam);
      }
#endif

      _ames_send(pac_u);
      break;
    }

    rai_u = rai_u->ai_next;
  }

  c3_free(adr_u);
  uv_freeaddrinfo(aif_u);
}

/* u3_ames_decode_lane(): deserialize noun to lane
*/
u3_lane
u3_ames_decode_lane(u3_atom lan) {
  u3_noun cud, tag, pip, por;

  cud = u3ke_cue(lan);
  u3x_trel(cud, &tag, &pip, &por);
  c3_assert( c3__ipv4 == tag );

  u3_lane lan_u;
  lan_u.pip_w = u3r_word(0, pip);

  c3_assert( _(u3a_is_cat(por)) );
  c3_assert( por < 65536 );
  lan_u.por_s = por;

  u3z(cud);
  return lan_u;
}

/* u3_ames_encode_lane(): serialize lane to jammed noun
*/
u3_atom
u3_ames_encode_lane(u3_lane lan) {
  return u3ke_jam(u3nt(c3__ipv4, u3i_words(1, &lan.pip_w), lan.por_s));
}

/* _ames_czar(): galaxy address resolution.
*/
static void
_ames_czar(u3_pact* pac_u, c3_c* bos_c)
{
  // XX revisit
  u3_pier* pir_u = u3_pier_stub();
  u3_ames* sam_u = pir_u->sam_u;

  pac_u->por_s = _ames_czar_port(pac_u->imp_y);

  if ( c3n == u3_Host.ops_u.net ) {
    pac_u->pip_w = 0x7f000001;
    _ames_send(pac_u);
    return;
  }

  //  if we don't have a galaxy domain, no-op
  //
  if ( 0 == bos_c ) {
    u3_noun nam = u3dc("scot", 'p', pac_u->imp_y);
    c3_c*  nam_c = u3r_string(nam);
    u3l_log("ames: no galaxy domain for %s, no-op\r\n", nam_c);

    c3_free(nam_c);
    u3z(nam);
    return;
  }

  time_t now = time(0);

  // backoff
  if ( (0xffffffff == sam_u->imp_w[pac_u->imp_y]) &&
       (now - sam_u->imp_t[pac_u->imp_y]) < 300 ) {
    _ames_pact_free(pac_u);
    return;
  }

  if ( (0 == sam_u->imp_w[pac_u->imp_y]) ||
       (now - sam_u->imp_t[pac_u->imp_y]) > 300 ) { /* 5 minute TTL */
    u3_noun  nam = u3dc("scot", 'p', pac_u->imp_y);
    c3_c*  nam_c = u3r_string(nam);
    // XX remove extra byte for '~'
    pac_u->dns_c = c3_malloc(1 + strlen(bos_c) + 1 + strlen(nam_c));

    snprintf(pac_u->dns_c, 256, "%s.%s", nam_c + 1, bos_c);
    // u3l_log("czar %s, dns %s\n", nam_c, pac_u->dns_c);

    c3_free(nam_c);
    u3z(nam);

    {
      uv_getaddrinfo_t* adr_u = c3_malloc(sizeof(*adr_u));
      adr_u->data = pac_u;

      c3_i sas_i;

      if ( 0 != (sas_i = uv_getaddrinfo(u3L, adr_u,
                                        _ames_czar_cb,
                                        pac_u->dns_c, 0, 0)) ) {
        u3l_log("ames: %s\n", uv_strerror(sas_i));
        _ames_czar_gone(pac_u, now);
        return;
      }
    }
  }
  else {
    pac_u->pip_w = sam_u->imp_w[pac_u->imp_y];
    _ames_send(pac_u);
    return;
  }
}

/* u3_ames_ef_bake(): notify %ames that we're live.
*/
void
u3_ames_ef_bake(u3_pier* pir_u)
{
  u3_noun pax = u3nq(u3_blip, c3__newt, u3k(u3A->sen), u3_nul);

  u3_pier_plan(pax, u3nc(c3__born, u3_nul));
}

/* u3_ames_ef_send(): send packet to network (v4).
*/
void
u3_ames_ef_send(u3_pier* pir_u, u3_noun lan, u3_noun pac)
{
  u3_ames* sam_u = pir_u->sam_u;

  if ( c3n == sam_u->liv ) {
    u3l_log("ames: not yet live, dropping outbound\r\n");
    u3z(lan); u3z(pac);
    return;
  }

  u3_pact* pac_u = c3_calloc(sizeof(*pac_u));
  pac_u->len_w   = u3r_met(3, pac);
  pac_u->hun_y   = c3_malloc(pac_u->len_w);

  u3r_bytes(0, pac_u->len_w, pac_u->hun_y, pac);

  u3_noun tag, val;
  u3x_cell(lan, &tag, &val);
  c3_assert( (c3y == tag) || (c3n == tag) );

  //  galaxy lane; do DNS lookup and send packet
  //
  if ( c3y == tag ) {
    c3_assert( c3y == u3a_is_cat(val) );
    c3_assert( val < 256 );

    pac_u->imp_y = val;
    _ames_czar(pac_u, sam_u->dns_c);
  }
  //  non-galaxy lane
  //
  else {
    u3_lane lan_u = u3_ames_decode_lane(u3k(val));
    //  convert incoming localhost to outgoing localhost
    //
    lan_u.pip_w = ( 0 == lan_u.pip_w )? 0x7f000001 : lan_u.pip_w;
    //  if in local-only mode, don't send remote packets
    //
    if ( (c3n == u3_Host.ops_u.net) && (0x7f000001 != lan_u.pip_w) ) {
      _ames_pact_free(pac_u);
    }
    //  otherwise, mutate destination and send packet
    //
    else {
      pac_u->pip_w = lan_u.pip_w;
      pac_u->por_s = lan_u.por_s;

      _ames_send(pac_u);
    }
  }
  u3z(lan); u3z(pac);
}

/* _ames_recv_cb(): receive callback.
*/
static void
_ames_recv_cb(uv_udp_t*        wax_u,
              ssize_t          nrd_i,
              const uv_buf_t * buf_u,
              const struct sockaddr* adr_u,
              unsigned         flg_i)
{
  // u3l_log("ames: rx %p\r\n", buf_u.base);

  if ( 0 == nrd_i ) {
    c3_free(buf_u->base);
  }
  //  check protocol version in header matches 0
  //
  else if ( 0 != (0x7 & *((c3_w*)buf_u->base)) ) {
    c3_free(buf_u->base);
  }
  else {
    {
      u3_noun msg = u3i_bytes((c3_w)nrd_i, (c3_y*)buf_u->base);

      // u3l_log("ames: plan\r\n");
#if 0
      u3z(msg);
#else
      u3_lane lan_u;
      struct sockaddr_in* add_u = (struct sockaddr_in *)adr_u;

      lan_u.por_s = ntohs(add_u->sin_port);
      lan_u.pip_w = ntohl(add_u->sin_addr.s_addr);
      u3_noun lan = u3_ames_encode_lane(lan_u);
      u3_noun mov = u3nt(c3__hear, u3nc(c3n, lan), msg);

      u3_pier_plan(u3nt(u3_blip, c3__ames, u3_nul), mov);
#endif
    }
    c3_free(buf_u->base);
  }
}

/* _ames_io_start(): initialize ames I/O.
*/
static void
_ames_io_start(u3_pier* pir_u)
{
  u3_ames* sam_u = pir_u->sam_u;
  c3_s     por_s = pir_u->por_s;
  u3_noun    who = u3i_chubs(2, pir_u->who_d);
  u3_noun    rac = u3do("clan:title", u3k(who));
  c3_i     ret_i;

  if ( c3__czar == rac ) {
    c3_y num_y = (c3_y)pir_u->who_d[0];
    c3_s zar_s = _ames_czar_port(num_y);

    if ( 0 == por_s ) {
      por_s = zar_s;
    }
    else if ( por_s != zar_s ) {
      u3l_log("ames: czar: overriding port %d with -p %d\n", zar_s, por_s);
      u3l_log("ames: czar: WARNING: %d required for discoverability\n", zar_s);
    }
  }

  if ( 0 != (ret_i = uv_udp_init(u3L, &sam_u->wax_u)) ) {
    u3l_log("ames: init: %s\n", uv_strerror(ret_i));
    c3_assert(0);
  }

  //  Bind and stuff.
  {
    struct sockaddr_in add_u;
    c3_i               add_i = sizeof(add_u);

    memset(&add_u, 0, sizeof(add_u));
    add_u.sin_family = AF_INET;
    add_u.sin_addr.s_addr = _(u3_Host.ops_u.net) ?
                              htonl(INADDR_ANY) :
                              htonl(INADDR_LOOPBACK);
    add_u.sin_port = htons(por_s);

    if ( (ret_i = uv_udp_bind(&sam_u->wax_u,
                              (const struct sockaddr*)&add_u, 0)) != 0 )
    {
      u3l_log("ames: bind: %s\n", uv_strerror(ret_i));

      if ( (c3__czar == rac) &&
           (UV_EADDRINUSE == ret_i) )
      {
        u3l_log("    ...perhaps you've got two copies of vere running?\n");
      }

      u3_pier_exit(pir_u);
    }

    uv_udp_getsockname(&sam_u->wax_u, (struct sockaddr *)&add_u, &add_i);
    c3_assert(add_u.sin_port);

    sam_u->por_s = ntohs(add_u.sin_port);
  }

  if ( c3y == u3_Host.ops_u.net ) {
    u3l_log("ames: live on %d\n", por_s);
  }
  else {
    u3l_log("ames: live on %d (localhost only)\n", por_s);
  }

  uv_udp_recv_start(&sam_u->wax_u, _ames_alloc, _ames_recv_cb);

  sam_u->liv = c3y;
  u3z(rac);
  u3z(who);
}

/* _cttp_mcut_char(): measure/cut character.
*/
static c3_w
_cttp_mcut_char(c3_c* buf_c, c3_w len_w, c3_c chr_c)
{
  if ( buf_c ) {
    buf_c[len_w] = chr_c;
  }
  return len_w + 1;
}

/* _cttp_mcut_cord(): measure/cut cord.
*/
static c3_w
_cttp_mcut_cord(c3_c* buf_c, c3_w len_w, u3_noun san)
{
  c3_w ten_w = u3r_met(3, san);

  if ( buf_c ) {
    u3r_bytes(0, ten_w, (c3_y *)(buf_c + len_w), san);
  }
  u3z(san);
  return (len_w + ten_w);
}

/* _cttp_mcut_path(): measure/cut cord list.
*/
static c3_w
_cttp_mcut_path(c3_c* buf_c, c3_w len_w, c3_c sep_c, u3_noun pax)
{
  u3_noun axp = pax;

  while ( u3_nul != axp ) {
    u3_noun h_axp = u3h(axp);

    len_w = _cttp_mcut_cord(buf_c, len_w, u3k(h_axp));
    axp = u3t(axp);

    if ( u3_nul != axp ) {
      len_w = _cttp_mcut_char(buf_c, len_w, sep_c);
    }
  }
  u3z(pax);
  return len_w;
}

/* _cttp_mcut_host(): measure/cut host.
*/
static c3_w
_cttp_mcut_host(c3_c* buf_c, c3_w len_w, u3_noun hot)
{
  len_w = _cttp_mcut_path(buf_c, len_w, '.', u3kb_flop(u3k(hot)));
  u3z(hot);
  return len_w;
}

/* u3_ames_ef_turf(): initialize ames I/O on domain(s).
*/
void
u3_ames_ef_turf(u3_pier* pir_u, u3_noun tuf)
{
  u3_ames* sam_u = pir_u->sam_u;

  if ( u3_nul != tuf ) {
    // XX save all for fallback, not just first
    u3_noun hot = u3k(u3h(tuf));
    c3_w  len_w = _cttp_mcut_host(0, 0, u3k(hot));

    sam_u->dns_c = c3_malloc(1 + len_w);
    _cttp_mcut_host(sam_u->dns_c, 0, hot);
    sam_u->dns_c[len_w] = 0;

    u3z(tuf);
  }
  else if ( (c3n == pir_u->fak_o) && (0 == sam_u->dns_c) ) {
    u3l_log("ames: turf: no domains\n");
  }

  if ( c3n == sam_u->liv ) {
    _ames_io_start(pir_u);
  }
}

/* u3_ames_io_init(): initialize ames I/O.
*/
void
u3_ames_io_init(u3_pier* pir_u)
{
  u3_ames* sam_u = pir_u->sam_u;
  sam_u->liv = c3n;
}

/* u3_ames_io_talk(): start receiving ames traffic.
*/
void
u3_ames_io_talk(u3_pier* pir_u)
{
  _ames_io_start(pir_u);
}

/* u3_ames_io_exit(): terminate ames I/O.
*/
void
u3_ames_io_exit(u3_pier* pir_u)
{
  u3_ames* sam_u = pir_u->sam_u;

  if ( c3y == sam_u->liv ) {
    uv_close(&sam_u->had_u, 0);
  }
}
