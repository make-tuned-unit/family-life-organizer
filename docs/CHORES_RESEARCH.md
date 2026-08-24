# Chores for kids — what the evidence says, and what Kinrows does about it

_Research brief prepared 2026-08-24 (primary sources checked; see "Sources").
This is the companion to `services/chores.js` the way the sleep-training
program's sources sit behind `services/sleepTraining.js`. Keep the two in sync._

## TL;DR — the product decisions

| Question | Evidence | What Kinrows does |
|---|---|---|
| Should a 3-year-old have a chore? | Yes. Rossmann 2002 (small, unreplicated): chores begun at 3–4 best predicted adult outcomes. White, DeBoer & Scharf 2019 (n≈9,971): kindergarten chores associated with competence at grade 3. Toddlers already help spontaneously (Warneken & Tomasello 2006; Coppens & Rogoff 2021). | One anchored chore at 2–3, done together; second chore at 4 once the first is steady. |
| Should the chore be paid? | No — every camp of the rewards literature agrees on this cell. Material reward cut 20-month-olds' helping from 89% → 53%, praise did not (Warneken & Tomasello 2008). Tangible, completion-contingent rewards undermine intrinsic motivation, *more* in children (Deci, Koestner & Ryan 1999, 128 studies). Rossmann herself: "not for an allowance". Lieber and Kobliner agree. | Allowance is a **fixed weekly amount, never docked** — the engine cannot do per-chore pay. Chores are framed as contribution. |
| Is $2/week reasonable? | Greenlight 2025: $6.18/wk average at age 5. Bingham & Whitebread 2013: money concepts consolidate ~7; Busby Grant & Suddendorf 2011: 3-year-olds don't yet hold "per week". | Keep $2 as a "family dividend"; hand it over visibly and count it together; the reinforcement for the chore is praise in the moment. |
| Is a $1 bedtime bonus a good idea? | No evidence for cash bedtime bonuses in preschoolers; delayed incentives lose their power (Levitt et al. 2016). The **Bedtime Pass** has an RCT at 3–6 (Moore, Friman et al. 2007) and sits in a literature where 94% of behavioural sleep interventions work (Mindell 2006). | Bonuses stay as a weekly "mostly went well" mechanic; the app points bedtime bonuses at the Bedtime Pass in the sleep-training program. |
| Is feeding the dog appropriate at 3? | Not unsupervised. AACAP lists pet feeding at 4–5, AAP at 5–7; food guarding is the top bite circumstance for familiar children under 6 (Reisner 2007); AAP: never bother a dog that is eating. | "Help feed the pet" is flagged **with a grown-up** under 5; "Fill the water bowl" is the pet job that is safely theirs; the program carries the never-near-a-dog-eating rule. |
| Streaks? | A single miss "did not materially affect" habit formation (Lally 2010, adults). Identity labels ("helper") backfire after setbacks (Foster-Hanson 2020). | The headline number is cumulative ("helped 47×"). The "ready for a second chore" nudge uses a 14-day steadiness share (≥80%), not an unbroken chain. No "failed"/"overdue" states. |
| How to add the second chore at 4? | Choice lifts motivation most in children, best with 2–4 options (Patall 2008); stacking on an existing cue works (Judah 2013; Wood & Neal 2007). | Suggestion chips per age band; copy says "let them pick from two or three, stack it on the one that works". |
| Sibling scoreboards? | Children read any comparison as "the sibling is slacking" (Sarmiento 2024); perceived fairness matters more than equality (McHale 2000; Loeser 2016). | One routine per child; each child sees only their own contributions. |
| Praise? | Process praise to 1–3-year-olds predicts motivation at 7–8 (Gunderson 2013). | Copy models "you filled the bowl right to the line", not "good helper". |

## What we deliberately do NOT claim

- **"Harvard study proves chores cause success."** A conflation of a TED talk with the Grant Study's "capacity to work" composite. Never used.
- **Causation from White et al. 2019.** It is an association with controls for sex, income and parent education.
- **Cognitive benefits of pet care specifically.** Tepper et al. 2022 found pet-care chores had no significant relationship with executive function (self-care and family-care chores did).
- **Any streak-loss statistic.** The circulating "40% abandon after a broken streak" figures are vendor blogs.
- **That chores reduce parents' load.** Untested; most parents of 1–4-year-olds report helping is sometimes unhelpful (Hammond & Brownell 2018). The mental-load win, per Daminger 2019, would come from removing the parent from *monitoring* — which is why chores are tickable from Home and by the Concierge/agents, not only from a dashboard.
- **The "$1 per year of age" rule.** Folklore; roughly tracks Greenlight's data for young kids, not for teens.

## Age bands (as shipped in `services/chores.js`)

| Band | Ages | Chores at once | Typical allowance | Next step |
|---|---|---|---|---|
| Little helper | 2–3 | 1–2, done together | Optional, $1–3 as a family dividend | 4th birthday + a steady record → let them pick a second chore |
| Growing independence | 4–5 | 2–3, some alone | $2–6 | By 6 they can own a chore with consequences |
| Real responsibility | 6–8 | 3–4, mostly independent | $4–8 | Multi-step chores from 9–10 |
| Running things | 9–12 | 4–6, independent | $8–12 | Owned domains as a teen |
| Owning a domain | 13+ | A few big responsibilities | $12–20+ as a managed budget | — |

Sources for the bands: AAP HealthyChildren (chores from 5), AACAP Facts for
Families #125, Cleveland Clinic 2022, University of Arkansas Extension, Child
Mind Institute. Montessori "practical life" is the frame for 2–3 (AMS publishes
no age chart and names no pet task).

## What competitors get wrong (App Store review themes, verified 2026-08-24)

Paywall after 15–20 minutes of setup (Chorsee, Joon, S'moresUp, Cozi); "charged
after I cancelled" (worst where billing bypasses Apple — BusyKid 3.4★);
money-linked apps are easy in, hard out (BusyKid $100 withdrawal chunks,
Greenlight age-18 cliff, CFPB investigation reported by ProPublica 2025); kids
gaming self-reported completion with every anti-cheat paywalled (Homey); no
one-device household support (Homey); gamification decays in 1–4 weeks (Joon);
no shared-custody support anywhere; silent abandonment (OurHome's backend died
Sept 2023 with no export). Kinrows' answers: no paywall on chores, no debit
card, parent-ticked from one phone, cumulative counts rather than a game,
multi-household by design, and a developer API so the data is never trapped.

## Sources

### Academic
- White, E. M., DeBoer, M. D., & Scharf, R. J. (2019). *J Dev Behav Pediatr*, 40(3), 176–182. https://doi.org/10.1097/DBP.0000000000000637
- Rossmann, M. (2002). *Involving children in household tasks.* University of Minnesota (press document, not peer-reviewed). https://ghk.h-cdn.co/assets/cm/15/12/55071e0298a05_-_Involving-children-in-household-tasks-U-of-M.pdf
- Tepper, Howell & Bennett (2022). *Aust Occup Ther J*, 69(5), 585–598. https://doi.org/10.1111/1440-1630.12822
- Warneken & Tomasello (2006). *Science*, 311, 1301–1303. https://doi.org/10.1126/science.1121448
- Warneken & Tomasello (2008). *Dev Psychol*, 44(6), 1785–1788. https://doi.org/10.1037/a0013860
- Dahl (2015). *Child Dev*, 86(4), 1080–1093. https://doi.org/10.1111/cdev.12361
- Hammond & Brownell (2018). *Front Psychol*, 9, 1770. https://doi.org/10.3389/fpsyg.2018.01770
- Coppens, Alcalá, Mejía-Arauz & Rogoff (2014). *Human Development*, 57, 116–130. https://doi.org/10.1159/000356768
- Coppens & Rogoff (2021). *Social Development*, 31, 656–678. https://doi.org/10.1111/sode.12566
- Coppens, Corwin & Alcalá (2020). *Front Psychol*, 11, 307. https://doi.org/10.3389/fpsyg.2020.00307
- Deci, Koestner & Ryan (1999). *Psych Bulletin*, 125(6), 627–668. https://doi.org/10.1037/0033-2909.125.6.627
- Cameron & Pierce (1994). *Rev Educ Res*, 64(3), 363–423. https://doi.org/10.3102/00346543064003363
- Fabes et al. (1989). *Dev Psychol*, 25, 509–515.
- Patall, Cooper & Robinson (2008). *Psych Bulletin*, 134(2), 270–300.
- Bryan, Master & Walton (2014). *Child Dev*, 85(5), 1836–1842. https://doi.org/10.1111/cdev.12244
- Foster-Hanson, Cimpian, Leshin & Rhodes (2020). *Child Dev*, 91(1), 236–248. https://doi.org/10.1111/cdev.13147
- Gunderson et al. (2013). *Child Dev*, 84(5), 1526–1541. https://doi.org/10.1111/cdev.12064
- Lally et al. (2010). *Eur J Soc Psychol*, 40(6), 998–1009. https://doi.org/10.1002/ejsp.674
- Wood & Neal (2007). *Psych Review*, 114(4), 843–863.
- Judah, Gardner & Aunger (2013). *Br J Health Psychol*, 18(2), 338–353.
- Zimmerman, Ledford & Barton (2017). *J Early Interv*, 39(4), 339–358.
- Fiese et al. (2002). *J Fam Psychol*, 16(4), 381–390.
- Mindell et al. (2006). *Sleep*, 29(10), 1263–1276.
- Moore, Friman, Fruzzetti & MacAleese (2007). *J Pediatr Psychol*, 32(3), 283–287. https://academic.oup.com/jpepsy/article/32/3/283/2951943
- Levitt, List, Neckermann & Sadoff (2016). *AEJ: Economic Policy*. https://www.nber.org/papers/w18165
- Reisner, Shofer & Nance (2007). *Injury Prevention*, 13(6), 348–351. https://doi.org/10.1136/ip.2007.015396
- Arhant, Beetz & Troxler (2017). *Front Vet Sci*, 4, 130. https://doi.org/10.3389/fvets.2017.00130
- McHale et al. (2000). *Social Development*, 9(2), 149–172.
- Loeser, Whiteman & McHale (2016). *J Child Fam Stud*, 25(8), 2405–2414.
- Sarmiento, Hwang & Midgette (2024). *J Marriage Fam*, 86(2), 433–454. https://doi.org/10.1111/jomf.12966
- Lam, Greene & McHale (2016). *Dev Psychol*, 52(12), 2071–2084.
- Daminger (2019). *Am Sociol Rev*, 84(4), 609–633. https://doi.org/10.1177/0003122419859007
- Busby Grant & Suddendorf (2011). *Early Child Res Q*, 26(1), 87–95.
- Bingham & Whitebread (2013). *Habit formation and learning in young children.* Money Advice Service.

### Guidance
- AAP HealthyChildren — chores by age; dog-bite prevention; choosing a pet.
- AACAP Facts for Families #125 (chores) and #75 (pets).
- Cleveland Clinic (2022), Child Mind Institute, University of Arkansas Extension, American Montessori Society, AVMA, FDA pet-food handling.
- Lieber, *The Opposite of Spoiled* (2015); Kobliner, *Make Your Kid a Money Genius*; Kohn, *Punished by Rewards* (1993).

### Market data
- Greenlight average allowance by age (2025 data); AICPA/Harris (2019); T. Rowe Price Parents, Kids & Money (2022); NatWest Rooster Money Pocket Money Index (2024/25); Pew (2019) teen time use; ProPublica (2025) on the CFPB/Greenlight investigation.
