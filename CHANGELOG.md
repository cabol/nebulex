# Changelog

## [v1.1.1](https://github.com/cabol/nebulex/tree/v1.1.1) (2019-11-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.1.0...v1.1.1)

**Implemented enhancements:**

- Add capability to limit cache size  [\#53](https://github.com/cabol/nebulex/issues/53)
- Ability to "get or set" a key [\#49](https://github.com/cabol/nebulex/issues/49)
- Multilevel Cache: transaction/3 is attempting to change all levels multiple times. [\#35](https://github.com/cabol/nebulex/issues/35)

**Fixed bugs:**

- Sporadic :badarg error [\#52](https://github.com/cabol/nebulex/issues/52)

**Closed issues:**

- Pre Expire Hook [\#57](https://github.com/cabol/nebulex/issues/57)
- Add matching option on returned result to Nebulex.Caching [\#55](https://github.com/cabol/nebulex/issues/55)
- Multi Level with dist not working as expected [\#54](https://github.com/cabol/nebulex/issues/54)
- Adapter for FoundationDB [\#51](https://github.com/cabol/nebulex/issues/51)

**Merged pull requests:**

- Add match option to Nebulex.Caching [\#56](https://github.com/cabol/nebulex/pull/56) ([polmiro](https://github.com/polmiro))

## [v1.1.0](https://github.com/cabol/nebulex/tree/v1.1.0) (2019-05-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.1...v1.1.0)

**Implemented enhancements:**

- Refactor flush action in the local adapter to delete all objects instead of deleting all generation tables [\#48](https://github.com/cabol/nebulex/issues/48)
- Write a guide for `Nebulex.Caching` [\#45](https://github.com/cabol/nebulex/issues/45)
- Turn `Nebulex.Adapter.NodeSelector` into a generic hash behavior `Nebulex.Adapter.Hash` [\#44](https://github.com/cabol/nebulex/issues/44)
- Turn `Nebulex.Adapters.Dist.RPC` into a reusable utility [\#43](https://github.com/cabol/nebulex/issues/43)
- Add support to evict multiple keys from cache in `defevict`  [\#42](https://github.com/cabol/nebulex/issues/42)

**Fixed bugs:**

- custom ttl on mulltilevel cache gets overwritten [\#46](https://github.com/cabol/nebulex/issues/46)

**Closed issues:**

- Will nebulex support replicating cache partitions? [\#47](https://github.com/cabol/nebulex/issues/47)
- Add support to define `:opts` in `defcacheable` and `defupdatable` [\#40](https://github.com/cabol/nebulex/issues/40)
- Random test failure - UndefinedFunctionError [\#28](https://github.com/cabol/nebulex/issues/28)
- Adapter for Memcached [\#22](https://github.com/cabol/nebulex/issues/22)
- Invalidate keys cluster-wide [\#18](https://github.com/cabol/nebulex/issues/18)

**Merged pull requests:**

- Fix error when running in a release [\#41](https://github.com/cabol/nebulex/pull/41) ([peburrows](https://github.com/peburrows))

## [v1.0.1](https://github.com/cabol/nebulex/tree/v1.0.1) (2019-01-11)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0...v1.0.1)

**Fixed bugs:**

- The `:infinity` atom is being set for unexpired object when is retrieved from an older generation [\#37](https://github.com/cabol/nebulex/issues/37)

**Closed issues:**

- Caching utility macros: `defcacheable`, `defevict` and `defupdatable` [\#39](https://github.com/cabol/nebulex/issues/39)
- Multilevel Cache: replicate/2 is attempting to subtract from :infinity [\#34](https://github.com/cabol/nebulex/issues/34)
- has\_key?/1 does not respect ttl [\#33](https://github.com/cabol/nebulex/issues/33)
- Add dialyzer and credo checks to the CI pipeline [\#31](https://github.com/cabol/nebulex/issues/31)
- Fix documentation about hooks [\#30](https://github.com/cabol/nebulex/issues/30)
- FAQ list [\#25](https://github.com/cabol/nebulex/issues/25)

**Merged pull requests:**

- typo in transaction docs [\#38](https://github.com/cabol/nebulex/pull/38) ([fredr](https://github.com/fredr))
- Handle an :infinity expiration in multilevel replication. [\#36](https://github.com/cabol/nebulex/pull/36) ([sdost](https://github.com/sdost))
- add missing coma in conf section of readme file [\#32](https://github.com/cabol/nebulex/pull/32) ([Kociamber](https://github.com/Kociamber))

## [v1.0.0](https://github.com/cabol/nebulex/tree/v1.0.0) (2018-10-31)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.3...v1.0.0)

**Implemented enhancements:**

- Refactor `Nebulex.Adapters.Dist` to use `Task` instead of `:rpc` [\#24](https://github.com/cabol/nebulex/issues/24)
- Create first cache generation by default when the cache is started [\#21](https://github.com/cabol/nebulex/issues/21)

**Closed issues:**

- Performance Problem. [\#27](https://github.com/cabol/nebulex/issues/27)
- Cache Failing to Start on Production [\#26](https://github.com/cabol/nebulex/issues/26)
- Adapter for Redis [\#23](https://github.com/cabol/nebulex/issues/23)
- For `update` and `get\_and\_update` functions, the :ttl is being overridden [\#19](https://github.com/cabol/nebulex/issues/19)
- TTL and EXPIRE functions? [\#17](https://github.com/cabol/nebulex/issues/17)
- Publish a rc.3 release [\#16](https://github.com/cabol/nebulex/issues/16)
- Replicated cache adapter [\#15](https://github.com/cabol/nebulex/issues/15)
- Fulfil the open-source checklist [\#1](https://github.com/cabol/nebulex/issues/1)

## [v1.0.0-rc.3](https://github.com/cabol/nebulex/tree/v1.0.0-rc.3) (2018-01-10)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.2...v1.0.0-rc.3)

**Closed issues:**

- Add stream [\#10](https://github.com/cabol/nebulex/issues/10)

## [v1.0.0-rc.2](https://github.com/cabol/nebulex/tree/v1.0.0-rc.2) (2017-11-25)

[Full Changelog](https://github.com/cabol/nebulex/compare/v1.0.0-rc.1...v1.0.0-rc.2)

**Closed issues:**

- Atom exhaustion from generations [\#8](https://github.com/cabol/nebulex/issues/8)
- Custom ttl for every cache record? [\#7](https://github.com/cabol/nebulex/issues/7)
- Load/Stress Tests [\#6](https://github.com/cabol/nebulex/issues/6)
- Update Getting Started guide [\#4](https://github.com/cabol/nebulex/issues/4)
- Add counters support – increments and decrements by a given amount [\#3](https://github.com/cabol/nebulex/issues/3)

## [v1.0.0-rc.1](https://github.com/cabol/nebulex/tree/v1.0.0-rc.1) (2017-07-30)

[Full Changelog](https://github.com/cabol/nebulex/compare/64dbc38a7e330bb15a1f7372c6d3a97b82d61cc4...v1.0.0-rc.1)

**Closed issues:**

- Implement mix task to automate cache generation [\#2](https://github.com/cabol/nebulex/issues/2)



\* *This Changelog was automatically generated by [github_changelog_generator](https://github.com/github-changelog-generator/github-changelog-generator)*
