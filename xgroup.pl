/*  File:    xgroup.pl
    Author:  Roy Ratcliffe
    Created: Dec 10 2024
    Purpose: Redis XGROUP CREATE command wrapper for Prolog

Copyright (c) 2024, Roy Ratcliffe, Northumberland, United Kingdom

Permission is hereby granted, free of charge,  to any person obtaining a
copy  of  this  software  and    associated   documentation  files  (the
"Software"), to deal in  the   Software  without  restriction, including
without limitation the rights to  use,   copy,  modify,  merge, publish,
distribute, sub-license, and/or sell copies  of   the  Software,  and to
permit persons to whom the Software is   furnished  to do so, subject to
the following conditions:

    The above copyright notice and this permission notice shall be
    included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT  WARRANTY OF ANY KIND, EXPRESS
OR  IMPLIED,  INCLUDING  BUT  NOT   LIMITED    TO   THE   WARRANTIES  OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR   PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS  OR   COPYRIGHT  HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY,  WHETHER   IN  AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM,  OUT  OF   OR  IN  CONNECTION  WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

*/

:- module(xgroup,
          [ xgroup_create/3, % +Redis:atom, +Key:atom, +Group:atom
            xgroup_create/4  % +Redis:atom, +Key:atom, +Group:atom, +Options:list
          ]).

/** <module> Redis XGROUP CREATE command wrapper

Wraps Redis's `XGROUP CREATE` command with `xgroup_create/3` and
`xgroup_create/4`. Translates Prolog options into Redis command arguments,
extracts stream `id/1` (default `$`), handles `mkstream(true)` and
`entriesread/1`, and captures optional reply. Behaves idempotently by
catching `BUSYGROUP` errors.

*/

%!  xgroup_create(+Redis:atom, +Key:atom, +Group:atom) is det.
%!  xgroup_create(+Redis:atom, +Key:atom, +Group:atom, +Options:list) is det.
%
%   Creates a consumer group for a Redis stream if it does not already exist.
%   This predicate attempts to create a consumer group named Group for the
%   stream identified by Key in the Redis instance specified by Redis. If the
%   consumer group already exists, the predicate succeeds without error.
%
%   The predicate can be called with or without the Options argument. If Options
%   is not provided, it defaults to an empty list. The Options argument allows
%   for additional customisation of the command execution, such as specifying
%   the ID for the consumer group, whether to create the stream if it does not
%   exist, and how many entries to read when the group is created.
%
%   Example usage:
%
%       % Create a consumer group named "mygroup" for the stream "mystream" in
%       % the Redis instance "myredis".
%       ?- xgroup_create(myredis, mystream, mygroup).
%
%   Delete a consumer group named "mygroup" for the stream "mystream" in the
%   Redis instance "myredis" using:
%
%       ?- redis(myredis, xgroup(destroy, mystream, mygroup), _).
%
%   @arg Redis The Redis instance identifier.
%   @arg Key The Redis stream key.
%   @arg Group The name of the consumer group to create.
%   @arg Options A list of options to customise the command execution.
%
%   Supported options include:
%
%       - id(Id) specifies the ID for the consumer group.
%         Defaults to '$' (the latest entry in the stream).
%       - mkstream(true) specifies that the stream should be created
%         if it does not already exist.
%       - entriesread(EntriesRead) specifies the number of entries to read
%         when the group is created.
%       - reply(Reply) specifies a variable to unify with the command's reply.
%         If not provided, the reply is ignored.

xgroup_create(Redis, Key, Group) :- xgroup_create(Redis, Key, Group, []).

xgroup_create(Redis, Key, Group, Options) :-
    % Construct the XGROUP CREATE command with the provided options. The command
    % is built as a Prolog term that will be passed to the redis/3 predicate for
    % execution. The options are processed to include the appropriate arguments
    % in the command term.
    %
    % The command structure is as follows:
    %
    %   XGROUP CREATE key group id|$ [MKSTREAM] [ENTRIESREAD entries-read]
    %
    (   option(mkstream(true), Options)
    ->  Options1 = [mkstream]
    ;   Options1 = []
    ),
    (   option(entriesread(EntriesRead), Options)
    ->  Options2 = [entriesread, EntriesRead|Options1]
    ;   Options2 = Options1
    ),
    option(id(Id), Options, $),
    Command =.. [xgroup, create, Key, Group, Id|Options2],
    option(reply(Reply), Options, _),
    catch(redis(Redis, Command, Reply),
          % Ignore "BUSYGROUP" error if the group already exists.
          % Still throw other errors, if any. This ensures idempotent behaviour.
          error(redis_error(busygroup, _), _), true).
