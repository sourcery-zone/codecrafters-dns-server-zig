[![progress-banner](https://backend.codecrafters.io/progress/dns-server/7280366d-0989-4882-9647-547c29cc8014)](https://app.codecrafters.io/users/codecrafters-bot?r=2qF)

## Live Streams

I live streamed more than 17 hours of my progress in ~1 hour sessions on Youtube.

<p align="center">
  <a href="https://www.youtube.com/playlist?list=PLvWC0OdoEeTgVkVMyvBSgvwv4_oVI0bkF">
    <img src="https://img.youtube.com/vi/Y4blRApX8jY/0.jpg" alt="Build to Learn: DNS Server in Zig - Playlist" />
  </a>
</p>

## My Notes

- ✅ [Session 1](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-1/)
- ✅ [Session 2](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-2/)
- ✅ [Session 3](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-3/)
- ✅ [Session 4](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-4/)
- ✅ [Session 5](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-5/)
- ✅ [Session 6, 7, and 8](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-6-7-and-8/)
- ✅ [Session 9, and 10](https://sourcery.zone/articles/2025/09/livestream-log-building-a-dns-server-in-zig-part-9-and-10/)
- ✅ [Sessions 11 to 17](https://sourcery.zone/articles/2025/10/livestream-log-building-a-dns-server-in-zig-conclusion/)

## CodeCrafter's Readme

This is a starting point for Zig solutions to the
["Build Your Own DNS server" Challenge](https://app.codecrafters.io/courses/dns-server/overview).

In this challenge, you'll build a DNS server that's capable of parsing and
creating DNS packets, responding to DNS queries, handling various record types
and doing recursive resolve. Along the way we'll learn about the DNS protocol,
DNS packet format, root servers, authoritative servers, forwarding servers,
various record types (A, AAAA, CNAME, etc) and more.

**Note**: If you're viewing this repo on GitHub, head over to
[codecrafters.io](https://codecrafters.io) to try the challenge.

# Passing the first stage

The entry point for your `your_program.sh` implementation is in `src/main.zig`.
Study and uncomment the relevant code, and push your changes to pass the first
stage:

```sh
git commit -am "pass 1st stage" # any msg
git push origin master
```

Time to move on to the next stage!

# Stage 2 & beyond

Note: This section is for stages 2 and beyond.

1. Ensure you have `zig (0.15)` installed locally
1. Run `./your_program.sh` to run your program, which is implemented in
   `src/main.zig`.
1. Commit your changes and run `git push origin master` to submit your solution
   to CodeCrafters. Test output will be streamed to your terminal.
