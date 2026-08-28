# Example 1 - a three-year office lease

Source: a synthetic decision written for this example. No real company, nothing
confidential, no third-party material. Both halves are real agent output on the
same facts. The BEFORE is what a general-purpose agent answered when the
decision was put to it directly, with no skill in play. The AFTER is what this
skill produced from the same facts. The BEFORE is abridged wherever you see an
ellipsis; the AFTER is part one only, which is the screen the reader is meant
to be able to stop at.

Kept because the BEFORE is good. That is the point of it. It is not a lazy
answer that a better prompt would fix - it is a careful, well-informed answer
that the person still cannot act on or audit.

## BEFORE - the same decision, no skill (~90 lines)

> ## The short version
>
> You're committing three years and roughly **$1.7-2.0M all-in**, backed by a
> **director's personal assets**, to test a hypothesis you cannot measure for
> 12-18 months, with **7.7 months of cash in the bank**, in a market that's
> discounting 15-20%, under a three-week deadline set by the counterparty.
>
> Almost every one of those factors independently argues for slowing down...
>
> *(Working from your numbers only. Two assumptions worth confirming: that the
> $310k burn excludes the office, and that $28k is net of service charge...)*
>
> ## 1. The cost model is missing 30-40%
> | Item | 3-year cost |
> | Base rent (your figure) | $1.04M |
> | Service charge, rates, insurance, utilities, cleaning | $250-450k |
> ... **Realistic total $1.8-2.2M**... **Runway impact.** $2.4M / $310k = 7.7
> months today... you're at **~5.8 months**...
>
> ## 2. The personal guarantee is the real tail risk
> ... **It bites precisely when the company fails.**... **It creates a live
> governance conflict.**...
>
> ## 3. Your own survey is telling you something you may be discounting
> ... Expect **4-8 regretted departures in year one**...
>
> ## 4. The diagnosis may be wrong, and it's cheap to check
> ... **55% retention on what denominator?** If it's 3 of 6 juniors, n=3 cannot
> carry a $2M decision...
>
> ## 5. The structure is backwards on timing
> ... **"Three weeks or it goes" is very likely manufactured.**...
>
> ## 6. Two execution details that quietly break the plan
> ... **The space is too big if the mandate fails and too small if it
> succeeds.**...
>
> ## What I'd actually recommend
>
> **Don't sign in three weeks.** Instead: 1. Buy the experiment, not the
> conclusion... 2. Fix the mentorship problem in parallel... 3. If you do
> lease, renegotiate as a tenant in a soft market...
>
> **Tripwires - agree these before you sign anything:** don't proceed if fewer
> than ~two-thirds of the 12 remote-contract staff agree in writing to new
> terms; if more than two senior mentors signal departure; if post-outlay
> runway is under 9 months without committed funding...

**What is wrong with it**

| Defect | Where |
|---|---|
| No verdict anywhere | Six sections of analysis, then the answer as the last heading. The reader has to reach the bottom to learn what to do |
| You cannot tell what was skipped | Six areas, chosen by the writer. Competitor response is never mentioned - considered and empty, or never looked at? Nothing says |
| Nothing is scored | Every risk is prose. Which is likeliest, which is worst, and which you would not see coming are three different questions, and the reader is left to separate them |
| The load-bearing belief is a footnote | "Two assumptions worth confirming" in italics under the opening. The one belief the whole $2M rests on is never isolated |
| Warnings nobody can act on | "Don't proceed if more than two senior mentors signal departure" - measured how, checked when, and by whom? |
| The ordinary failures are never swept | The class of decision is never named, so the ways this kind of deal usually dies are never worked through as a list |

## AFTER - os-what-could-go-wrong, part one (23 lines)

> # What could go wrong - signing a 3-year, $1.04M city-centre lease with a personal guarantee
>
> | | |
> |---|---|
> | **Verdict** | **Think again** |
> | **Why** | The company has 7.7 months of cash and is about to sign a 36-month personal guarantee with no break clause. The commitment outlives the funded life of the business by more than two years. |
> | **Worst case** | The company runs out of money around month 8. The landlord calls the guarantee. One director is personally liable for roughly **$650,000-$815,000**, plus make-good costs and legal fees. Before that, ~$348,000 of cash leaves the building before anyone sets foot in it, and around 7 people - weighted toward the seniors the juniors were supposed to learn from - have already gone. |
>
> **The biggest risks**
>
> 1. Cash $2,400,000 / burn $310,000 = **7.7 months of runway** against a
>    36-month obligation. Nothing in the brief says where money for months
>    8-36 comes from. (risk 1)
> 2. The two ways out both fail. Sublease comps are already **15-20% below
>    asking**, and a guarantee normally survives a sublet. (risk 2)
> 3. The three-week deadline forecloses roughly **$300,000-$412,000** of
>    negotiable value and, more importantly, the guarantee cap and break
>    clause that would make risks 1 and 2 survivable. (risk 3)
>
> **The thing nobody is questioning**
>
> That there will be more money. The brief prices the rent to the dollar and
> never states the runway, the revenue, or the raise - yet every number in it
> silently assumes funding that is not mentioned, not sized, and not made a
> condition of signing.
>
> **Fix before you commit**
>
> - Write down the funding plan for months 8-36 and make signing conditional
>   on it. If it isn't closed, do not sign. (risk 1)
> - Cap the personal guarantee at 6-12 months' rent, or make it burn off after
>   18-24 months of on-time payment. (risk 1)
> - Get a break clause at month 18 or 24. Without one there is no month-12
>   decision, because there is no month-12 action. (risks 2, 7)
> - Decide the 12 remote contracts **before** the announcement, in writing.
>   If they are exempt, the 80% target is arithmetically impossible: 28 of 40
>   is 70%. (risk 5)
> - Read every junior exit interview from the last 24 months and count the
>   stated reasons. Two days of work, and it tests the causal claim the whole
>   $1.2M rests on. (risk 4)

(Underneath part one, the same report carries the nine-area record of what was
checked, seven risk cards, and the cross-cutting findings. The reader who stops
at the screen above still has the verdict, the three worst risks, and the list
of things to do before signing.)

## What this example changed in the format

1. **The outside-view section exists because of this run.** The report attacked
   the reference class properly - standard commercial-lease practice on
   guarantees, the documented pattern of return-to-office mandates losing the
   most marketable staff - but all of it was buried inside individual cards.
   Asked directly, the agent confirmed: "No standalone section named the
   reference class." A reader could not check whether the ordinary ways this
   kind of deal dies had been swept. It is now a section of its own, and the
   cards cite it.
2. **Every line of "Fix before you commit" carries its risk number.** Without
   them the list reads as loose advice. With them, each item can be traced
   back to the mechanism that earned it, and an item with no card behind it is
   visible as padding.
3. **Part one has to survive being read alone.** The verdict, the worst case,
   the three risks, the one hidden belief and the actions all fit on a screen.
   Everything below it is working, not answer. That split is what lets someone
   who does not read contracts use the same report as the person who does.
4. **The empty areas are worth as much as the full ones.** In this run
   "people misusing it" and "what others do about it" produced no risk that
   kills the decision on its own. Saying so, and saying what was found instead,
   is the difference between a sweep and a list of whatever came to mind.
