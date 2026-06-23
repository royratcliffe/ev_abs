
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
    setting(device, Device),
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
    Value1 is ((Value - Minimum) / (Maximum - Minimum)) * 2 - 1,
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
    ->  redis(default, xadd(ev_abs, *, stick, Stick, Axis, Value1, OtherAxis, OtherValue), _)
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
