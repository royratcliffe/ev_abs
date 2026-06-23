:- module(ev_abs, []).
:- autoload(library(broadcast), [listen/2, unlisten/1]).
:- autoload(library(redis), [redis_server/3, redis/3, redis/2]).
:- autoload(library(redis_streams), [xlisten_group/5]).
:- use_module(library(debug), [debug/3]).
:- use_module(library(settings), [setting/4, setting/2]).
:- use_module(xgroup).

:- setting(rediscli_host, atom, env('REDISCLI_HOST', localhost),
           'Host of the Redis server').
:- setting(rediscli_port, integer, env('REDISCLI_PORT', 6379),
           'Port of the Redis server').

:- setting(input_event_key, atom, input_event,
    'Redis stream key to listen to for input events').
:- setting(input_event_group, atom, ev_abs,
    'Redis consumer group for input events').
:- setting(input_event_consumer, atom, env('HOSTNAME', ev_abs_consumer),
    'Name to use for consuming input events').

:- setting(ev_abs_key, atom, ev_abs,
    'Redis stream key to publish EV_ABS events to').

% Connect to Redis server at Host:Port with version 3 compatibility.
% This assumes the Redis server is running on the specified port.
redis_server :-
    setting(rediscli_host, Host),
    setting(rediscli_port, Port),
    redis_server(default, Host:Port, [version(3)]).

:- initialization(main, main).

% Initially disable debugging for the ev(abs) topic. It can be enabled via
% command line --verbose option.
:- nodebug(ev(abs)).
:- nodebug(input_event(entry)).

opt_type(v, verbose, boolean).
opt_type(verbose, verbose, boolean).

opt_help(verbose, 'Enable verbose output').

main(Argv) :-
    argv_options(Argv, [], Options),
    (   option(verbose(true), Options)
    ->  debug(ev(abs))
    ;   true
    ),
    redis_server,
    create_input_event_xgroup,
    listen_to_input_event,
    xlisten_input_event_group.

create_input_event_xgroup :- create_input_event_xgroup(default).

create_input_event_xgroup(Redis) :-
    setting(input_event_key, Key),
    setting(input_event_group, Group),
    xgroup_create(Redis, Key, Group, [id($), mkstream(true)]).

xlisten_input_event_group :- xlisten_input_event_group(default).

xlisten_input_event_group(Redis) :-
    setting(input_event_key, Key),
    setting(input_event_group, Group),
    setting(input_event_consumer, Consumer),
    xlisten_group(Redis, Group, Consumer, [Key], [starts([>])]).

listen_to_input_event :-
    unlisten_to_input_event,
    setting(input_event_key, Key),
    listen(redis_consume(Key, Entry, _), input_event(Entry)).

unlisten_to_input_event :-
    setting(input_event_key, Key),
    unlisten(redis_consume(Key, _, _)).

%! input_event(+Entry) is det.
% Consume input events from joysticks (or other EV_ABS devices) and update the
% joystick states accordingly. Ignore non-absolute events. The input event is a
% Redis stream entry with the following fields:
% - device: The device name.
% - typename: The type name of the event (should be 'EV_ABS').
% - codename: The code name of the event (e.g., 'ABS_X', 'ABS_Y', 'ABS_RX',
%   'ABS_RY', 'ABS_Z', 'ABS_RZ').
% - value: The value of the event.
% - absinfo_minimum: The minimum value for the axis.
% - absinfo_maximum: The maximum value for the axis. @arg Entry The input event
%   Redis stream entry.
input_event(Entry) :-
    debug(input_event(entry), '~k', [Entry]),
    redis{device:Device,
          typename:'EV_ABS',
          codename:CodeName,
          value:Value,
          absinfo_minimum:Minimum,
          absinfo_maximum:Maximum} :< Entry,
    codename_stick_axis(CodeName, StickUpper, Axis),
    !,
    % Convert the stick name to lower case and remove any leading or trailing
    % underscores. For example, the stick for axis 'ABS_X' becomes 'abs'.
    string_lower(StickUpper, StickLower),
    split_string(StickLower, "", "_", [Stick]),
    % Normalise the value to the range. Minimum and Maximum equal the minimum
    % and maximum values for the axis, which are typically -32768 and 32767
    % respectively for joystick axes. The normalised value is in the range [-1,
    % 1]. For trigger axes, the minimum and maximum values are typically 0 and
    % 255 respectively, and the normalised value is in the range [0, 1].
    (   Minimum < 0
    ->  Value1 is ((Value - Minimum) / (Maximum - Minimum)) * 2 - 1
    ;   Value1 is (Value - Minimum) / (Maximum - Minimum)
    ),
    (   redis(default, get(ev_abs:Stick:Axis), Value0)
    ->  debug(ev(abs), '~w ~w: ~w --> ~w', [Stick, Axis, Value0, Value1])
    ;   debug(ev(abs), '~w ~w: ~w', [Stick, Axis, Value1])
    ),
    redis(default, set(ev_abs:Stick:Axis, Value1)),
    % Broadcast the updated axis values to any listeners. Only broadcast if both
    % axes have values. Otherwise, only half of the stick has been moved; do not
    % broadcast a half-move.
    other_axis(Axis, OtherAxis),
    (   redis(default, get(ev_abs:Stick:OtherAxis), OtherValue)
    ->  redis(default, xadd(ev_abs, *, device, Device, stick, Stick, Axis, Value1, OtherAxis, OtherValue), _)
    ;   true
    ).
input_event(_).

%! codename_stick_axis(+CodeName, -Stick, -Axis) is semidet.
% True if CodeName is the code name for an axis, Stick is the corresponding
% stick, and Axis is the corresponding axis (x or y). Uses the naming convention
% that code names for x axes end with
% 'X' and code names for y axes end with 'Y'.
% @arg CodeName The code name for the axis.
% @arg Stick The corresponding stick.
% @arg Axis The corresponding axis (x or y).
codename_stick_axis(CodeName, Stick, x) :- atom_concat(Stick, 'X', CodeName), !.
codename_stick_axis(CodeName, Stick, y) :- atom_concat(Stick, 'Y', CodeName).

%! other_axis(+Axis1, -Axis2) is semidet.
% True if Axis1 and Axis2 are the two axes of a stick.
% @arg Axis1 The first axis.
% @arg Axis2 The second axis.
other_axis(x, y).
other_axis(y, x).
