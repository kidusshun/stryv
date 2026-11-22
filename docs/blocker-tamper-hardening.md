# Blocker Tamper Hardening (Future Plan)

Status: **not scheduled**. The first macOS blocker ships with launchd `KeepAlive` only. This document collects the options for making an active block harder to break, so we can pick them up later.

## Goal and honest limits

Once a block starts, nothing in Stryv can end it early. The weak point is the user being an **admin**. An admin can always defeat software on their own Mac. In the worst case they boot into Recovery and delete the files. So the goal is not "impossible". The goal is to **make a bypass take several deliberate, specific steps**, so that a moment of impulse is never enough.

Hardening should defeat these, roughly from easiest to hardest:

1. Quitting or deleting the Stryv app.
2. Rebooting.
3. Editing `/etc/hosts`.
4. `sudo kill` / `sudo killall` on the daemon.
5. `sudo launchctl bootout system/<label>` (removes the daemon from launchd).
6. Deleting the daemon's binary, its plist or the state file.
7. Moving the system clock forward.
8. Turning the daemon off under System Settings → General → Login Items (needs an admin password).

The baseline design already handles 1–3 and 7: a root daemon, state saved in a root-owned location, an instant restore when hosts is edited, and a check that compares the wall clock with a monotonic clock. The approaches below are for 4–8.

## Approaches

### 1. launchd KeepAlive (baseline, already planned)

- The LaunchDaemon plist has `KeepAlive = true` and `RunAtLoad = true`.
- **Defeats:** `kill`, `killall` and crashes. launchd restarts the daemon within about a second.
- **Doesn't defeat:** `launchctl bootout`, which unloads the job entirely until the next boot or bootstrap.
- **Cost:** none.

### 2. Hosts entries outlive the daemon (baseline, already planned)

- The daemon never removes the blocked entries from `/etc/hosts` when it exits. It removes them only after the block's end time.
- **Defeats:** "just stop the daemon". Booting it out leaves every site blocked, so the user also has to edit hosts by hand.
- **Cost:** none. It's a rule the daemon follows: no cleanup on SIGTERM.

### 3. Locked files with `schg` (preferred next step)

macOS (BSD) supports the **system immutable** flag. While it's set, *nobody* can modify, rename or delete the file, not even root, until the flag is cleared.

- **At block start**, the daemon (already root) runs the equivalent of `chflags schg` on:
  - `/private/etc/hosts`
  - the daemon binary in `/Library/PrivilegedHelperTools/`
  - the LaunchDaemon plist in `/Library/LaunchDaemons/`
  - the state file and its folder in `/Library/Application Support/Stryv/`
- **When the daemon itself needs to write** (to rewrite hosts or save state), it clears the flag, writes, and sets the flag again in one sequence. Use `chflags(2)` / `lchflags(2)` directly, not a shell-out.
- **At block end**, the daemon clears all the flags.
- **On boot**, if the saved block is still active, the daemon sets the flags again, in case a reinstall or migration stripped them.

How it fits with the file watcher: if someone clears `schg` and edits hosts, the kqueue watcher fires and the daemon restores the managed section straight away.

Limits:

- macOS runs at `securelevel 0`, so **root can clear `schg`** with `sudo chflags noschg <file>`. This is friction, not a wall. A bypass now needs: knowing the flag exists, clearing it on several files, booting out the daemon, and editing hosts, all before anything restores it.
- `uchg` (the user immutable flag) is weaker, because the file owner can clear it. Use `schg`.
- Some tools (installers, `brew`, editors) will fail on an immutable hosts file during a block. That's acceptable, but the in-app message should explain it.

**Cost:** low. It's a few syscalls in the daemon plus tests. This is the best value for the effort.

### 4. Watchdog daemon pair

- There are two LaunchDaemons, `com.stryv.blockd` and `com.stryv.blockd.guard`.
- Each one checks that the other is loaded, using `launchctl print system/<other>` or, better, a long-lived XPC connection whose invalidation handler fires when the peer goes away.
- If one is booted out, the survivor bootstraps it again from its plist. If the plist or binary is missing, the survivor restores it from a root-owned backup copy.
- **Defeats:** `launchctl bootout` of a single daemon.
- **Doesn't defeat:** booting out both in one command (`sudo launchctl bootout system/a; sudo launchctl bootout system/b`). Combined with `schg` on both plists and binaries, it still takes several steps.
- **Cost:** medium. A bug here can cause relaunch loops, and it makes development and uninstall more awkward. This needs a separate debug label and an uninstall path that only works when no block is active.

### 5. Don't depend on the app bundle

- Copy the daemon into `/Library/PrivilegedHelperTools/` (root-owned) instead of running it from inside the app with `SMAppService.daemon()`.
- **Why:** admin users can delete apps from `/Applications` **without a password prompt**, because `/Applications` is writable by the admin group. If the daemon binary lived inside the bundle, deleting the app would break the daemon.
- **Cost:** none. This is already planned.

### 6. Standard (non-admin) daily account (the only real lock)

- Use a **standard** account day to day. Keep a separate admin account whose password is somewhere inconvenient: written down in another room, held by a friend, or in a time-locked note.
- Without admin rights, `sudo`, `launchctl bootout`, `chflags noschg`, editing hosts and the Login Items toggle all stop working. Nothing above can be bypassed.
- **Cost:** some day-to-day friction (installing software asks for the admin login). No code needed. Stryv could have an onboarding page explaining how to set it up.

### 7. Removing admin rights automatically during a block (not recommended)

- During a block, the daemon would run `dseditgroup -o edit -d <user> -t user admin` and add the user back afterwards.
- **Why not:** if the daemon crashes, has a bug, or the Mac dies before the user is added back, you lose admin rights for good, and the fix goes through Recovery. On Apple Silicon, demoting the only admin or Secure Token holder can also cause FileVault and update problems. The risk far outweighs the benefit.

### Ruled out

- **Endpoint Security / blocking `launchctl` itself:** needs an Apple-granted entitlement that personal developer accounts don't get.
- **Network Extension content filter as the enforcer:** an admin can still turn it off in System Settings. It's no harder to bypass and much more work.
- **MDM / non-removable configuration profiles:** "removal disallowed" is only honored on supervised, MDM-enrolled Macs.

## Suggested order when we pick this up

1. `schg` locked files (approach 3).
2. Watchdog pair (approach 4), if `schg` alone isn't enough.
3. Onboarding page for the standard account (approach 6).

## Safety rails (required before shipping any of this)

Hardening turns bugs into lockouts. Before enabling it:

- **Keep the block length cap** (24h) in the daemon, not just in the UI.
- **Separate debug daemon:** Debug builds install `com.stryv.blockd.debug` with a 2-minute maximum block and no `schg`, so development never risks a real lockout.
- **Tests** for every transition: start, merge, expiry, restart mid-block, clock jump, flags set and cleared, expiry while asleep.
- **Emergency recovery doc** (kept outside the app UI), covering what to do if a bug leaves a block stuck past its end time:
  1. `sudo chflags noschg` on the files listed in approach 3.
  2. `sudo launchctl bootout` on each Stryv daemon.
  3. Remove the `# >>> Stryv` section from `/etc/hosts`.
  4. `sudo dscacheutil -flushcache; sudo killall -HUP mDNSResponder`.
