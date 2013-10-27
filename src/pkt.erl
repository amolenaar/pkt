%% Copyright (c) 2009-2013, Michael Santos <michael.santos@gmail.com>
%% All rights reserved.
%%
%% Redistribution and use in source and binary forms, with or without
%% modification, are permitted provided that the following conditions
%% are met:
%%
%% Redistributions of source code must retain the above copyright
%% notice, this list of conditions and the following disclaimer.
%%
%% Redistributions in binary form must reproduce the above copyright
%% notice, this list of conditions and the following disclaimer in the
%% documentation and/or other materials provided with the distribution.
%%
%% Neither the name of the author nor the names of its contributors
%% may be used to endorse or promote products derived from this software
%% without specific prior written permission.
%%
%% THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS
%% "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT
%% LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
%% FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE
%% COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT,
%% INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING,
%% BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
%% LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
%% CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT
%% LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN
%% ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE
%% POSSIBILITY OF SUCH DAMAGE.
-module(pkt).

-include("pkt.hrl").

-export([
        checksum/1,
        decapsulate/1, decapsulate/2,
        decode/1, decode/2,
        makesum/1,
        ether/1,
        ether_type/1,
        arp/1,
        null/1,
        gre/1,
        linux_cooked/1,
        icmp/1,
        icmp6/1,
        ipv4/1,
        ipv6/1,
        ipv6_ah/1,
        ipv6_dstopts/1,
        ipv6_esp/1,
        ipv6_fragment/1,
        ipv6_hopopts/1,
        ipv6_routing/1,
        ipproto/1, proto/1,
        tcp/1,
        tcp_options/1,
        udp/1,
        sctp/1,
        dlt/1, link_type/1
]).

% For integers, assume a whole frame and check the datalink type.
%
% Atoms can indicate any protocol type.
decapsulate(Proto, Data) ->
    decapsulate({Proto, Data}).

decapsulate({DLT, Data}) when is_integer(DLT) ->
    decapsulate_next({dlt(DLT), Data}, []);
decapsulate({Proto, Data}) when is_atom(Proto) ->
    decapsulate_next({Proto, Data}, []);
decapsulate(Data) when is_binary(Data) ->
    decapsulate_next({ether, Data}, []).

% Aliases
decapsulate_next({en10mb, Data}, Headers) ->
    decapsulate_next({ether, Data}, Headers);
decapsulate_next({linux_sll, Data}, Headers) ->
    decapsulate_next({linux_cooked, Data}, Headers);

% Protocol header indicates next header
decapsulate_next({null, Data}, Headers) ->
    {Header, Payload} = null(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({linux_cooked, Data}, Headers) ->
    {Header, Payload} = linux_cooked(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ether, Data}, Headers) ->
    {Header, Payload} = ether(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);

decapsulate_next({ipv4, Data}, Headers) ->
    {Header, Payload} = ipv4(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6, Data}, Headers) ->
    {Header, Payload} = ipv6(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);

decapsulate_next({ipv6_ah, Data}, Headers) ->
    {Header, Payload} = ipv6_ah(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6_dstopts, Data}, Headers) ->
    {Header, Payload} = ipv6_dstopts(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6_esp, Data}, Headers) ->
    {Header, Payload} = ipv6_esp(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6_fragment, Data}, Headers) ->
    {Header, Payload} = ipv6_fragment(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6_hopopts, Data}, Headers) ->
    {Header, Payload} = ipv6_hopopts(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);
decapsulate_next({ipv6_routing, Data}, Headers) ->
    {Header, Payload} = ipv6_routing(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);

decapsulate_next({gre, Data}, Headers) ->
    {Header, Payload} = gre(Data),
    decapsulate_next({next(Header), Payload}, [Header|Headers]);

% Upper layer: data follows header
decapsulate_next({arp, Data}, Headers) ->
    {Header, Payload} = arp(Data),
    lists:reverse([Payload, Header|Headers]);
decapsulate_next({tcp, Data}, Headers) ->
    {Header, Payload} = tcp(Data),
    lists:reverse([Payload, Header|Headers]);
decapsulate_next({udp, Data}, Headers) ->
    {Header, Payload} = udp(Data),
    lists:reverse([Payload, Header|Headers]);
decapsulate_next({sctp, Data}, Headers) ->
    {Header, Payload} = sctp(Data),
    lists:reverse([Payload, Header|Headers]);
decapsulate_next({icmp, Data}, Headers) ->
    {Header, Payload} = icmp(Data),
    lists:reverse([Payload, Header|Headers]);
decapsulate_next({icmp6, Data}, Headers) ->
    {Header, Payload} = icmp6(Data),
    lists:reverse([Payload, Header|Headers]);
% IPv6 NONE pseudo-header
decapsulate_next({ipv6_none, Data}, Headers) ->
    lists:reverse([Data|Headers]).

decode(Data) when is_binary(Data) ->
    decode(ether, Data).

decode(Proto, Data) when is_atom(Proto) ->
    try decode_next({Proto, Data}, []) of
        N ->
            N
    catch
        error:_ ->
            {error, [], {unsupported, Data}}
    end.

% Aliases
decode_next({en10mb, Data}, Headers) ->
    decode_next({ether, Data}, Headers);
decode_next({linux_sll, Data}, Headers) ->
    decode_next({linux_cooked, Data}, Headers);

% Protocol header indicates next header
decode_next({Proto, Data}, Headers) when
    Proto =:= ether;
    Proto =:= gre;
    Proto =:= ipv4;
    Proto =:= ipv6;
    Proto =:= linux_cooked;
    Proto =:= null;

    Proto =:= ipv6_ah;
    Proto =:= ipv6_dstopts;
    Proto =:= ipv6_esp;
    Proto =:= ipv6_fragment;
    Proto =:= ipv6_hopopts;
    Proto =:= ipv6_routing ->

    Decode = try ?MODULE:Proto(Data) of
        N ->
            {ok, N}
    catch
        error:_ ->
            {error, lists:reverse(Headers), {Proto, Data}}
    end,

    case Decode of
        {ok, {Header, Payload}} ->
            try next(Header) of
                Next ->
                    decode_next({Next, Payload}, [Header|Headers])
            catch
                error:_ ->
                    {error, lists:reverse([Header|Headers]), {unsupported, Payload}}
            end;
        {error, _, _} = Error ->
            Error
    end;

% Upper layer: data follows header

% IPv6 NONE pseudo-header
decode_next({ipv6_none, Data}, Headers) ->
    {ok, {lists:reverse(Headers), Data}};

decode_next({Proto, Data}, Headers) when
    Proto =:= arp;
    Proto =:= icmp;
    Proto =:= icmp6;
    Proto =:= sctp;
    Proto =:= sctp;
    Proto =:= tcp;
    Proto =:= udp ->
    try ?MODULE:Proto(Data) of
        {Header, Payload} ->
            {ok, {lists:reverse([Header|Headers]), Payload}}
    catch
        error:_ ->
            {error, lists:reverse(Headers), {Proto, Data}}
    end.

next(#null{family = Family}) -> family(Family);
next(#linux_cooked{pro = Pro}) -> ether_type(Pro);
next(#ether{type = Type}) -> ether_type(Type);
next(#ipv4{p = P}) -> ipproto(P);
next(#gre{type = Type}) -> ether_type(Type);
next(#ipv6{next = Next}) -> ipproto(Next);
next(#ipv6_ah{next = Next}) -> ipproto(Next);
next(#ipv6_dstopts{next = Next}) -> ipproto(Next);
next(#ipv6_esp{next = Next}) -> ipproto(Next);
next(#ipv6_fragment{next = Next}) -> ipproto(Next);
next(#ipv6_hopopts{next = Next}) -> ipproto(Next);
next(#ipv6_routing{next = Next}) -> ipproto(Next).

%% BSD loopback
null(N) ->
    pkt_null:codec(N).

%% Linux cooked capture ("-i any") - DLT_LINUX_SLL
linux_cooked(N) ->
    pkt_linux_cooked:codec(N).

%% Ethernet
ether(N) ->
    pkt_ether:codec(N).

ether_type(N) ->
    pkt_ether:type(N).

%% ARP
arp(N) ->
    pkt_arp:codec(N).

%% IPv4
ipv4(N) ->
    pkt_ipv4:codec(N).


%% IPv6
ipv6(N) ->
    pkt_ipv6:codec(N).

ipv6_ah(N) ->
    pkt_ipv6_ah:codec(N).
ipv6_dstopts(N) ->
    pkt_ipv6_dstopts:codec(N).
ipv6_esp(N) ->
    pkt_ipv6_esp:codec(N).
ipv6_fragment(N) ->
    pkt_ipv6_fragment:codec(N).
ipv6_hopopts(N) ->
    pkt_ipv6_hopopts:codec(N).
ipv6_routing(N) ->
    pkt_ipv6_routing:codec(N).

%% GRE
gre(N) ->
    pkt_gre:codec(N).

%% TCP
tcp(N) ->
    pkt_tcp:codec(N).

tcp_options(N) ->
    pkt_tcp:options(N).

%% SCTP
sctp(N) ->
    pkt_sctp:codec(N).

%% UDP
udp(N) ->
    pkt_udp:codec(N).

%% ICMP
icmp(N) ->
    pkt_icmp:codec(N).

%% ICMPv6
icmp6(N) ->
    pkt_icmp6:codec(N).

%% Datalink types
link_type(N) ->
    dlt(N).

dlt(N) ->
    pkt_dlt:codec(N).

%% IP protocols
proto(N) ->
    ipproto(N).

ipproto(N) ->
    pkt_ipproto:codec(N).

%% Protocol families
family(?PF_INET) -> ipv4;
family(?PF_INET6) -> ipv6.

%%
%% Utility functions
%%

% TCP pseudoheader checksum
checksum([#ipv4{
        saddr = {SA1,SA2,SA3,SA4},
        daddr = {DA1,DA2,DA3,DA4},
        len = IPLen,
        hl = HL
    },
    #tcp{
        off = Off
    } = TCPhdr,
    Payload
]) ->
    Len = IPLen - (HL * 4),
    PayloadLen = IPLen - ((HL * 4) + (Off * 4)),
    Pad = case Len rem 2 of
        0 -> 0;
        1 -> 8
    end,
    TCP = tcp(TCPhdr),
    checksum(
        <<SA1,SA2,SA3,SA4,
          DA1,DA2,DA3,DA4,
          0:8,
          ?IPPROTO_TCP:8,
          Len:16,
          TCP/binary,
          Payload:PayloadLen/binary,
          0:Pad>>
    );

% UDP pseudoheader checksum
checksum([#ipv4{
        saddr = {SA1,SA2,SA3,SA4},
        daddr = {DA1,DA2,DA3,DA4}
    },
    #udp{
        ulen = Len
    } = Hdr,
    Payload
]) ->
    UDP = udp(Hdr),
    Pad = case Len rem 2 of
        0 -> 0;
        1 -> 8
    end,
    checksum(
        <<SA1,SA2,SA3,SA4,
          DA1,DA2,DA3,DA4,
          0:8,
          ?IPPROTO_UDP:8,
          Len:16,
          UDP/binary,
          Payload/bits,
          0:Pad>>
    );

checksum(#ipv4{} = H) ->
    checksum(ipv4(H));
checksum(Hdr) ->
    lists:foldl(fun compl/2, 0, [ W || <<W:16>> <= Hdr ]).

makesum(Hdr) -> 16#FFFF - checksum(Hdr).

compl(N) when N =< 16#FFFF -> N;
compl(N) -> (N band 16#FFFF) + (N bsr 16).
compl(N,S) -> compl(N+S).
