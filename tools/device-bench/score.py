#!/usr/bin/env python3
"""Scores a bench run: latency (end of speech -> final text) and quality.

  score.py <cases.json> --device <results.tsv> [--label iphone] [--load <load.tsv>]
  score.py <cases.json> --mac <v3.tsv> <polish-harness-show.txt> [--label mac]

Several runs can be given in one call (each --device / --mac adds one); they are printed
side by side with the same rules. All figures have 5 decimals.

Total = transcription time of the whole clip + polish engine time, as on the Mac bench:
the clip is transcribed after the speaker stops, then polished. A skipped model counts 0 ms.
"""
import csv, json, re, sys, statistics as st

csv.field_size_limit(10**9)


def q(xs, p):
    xs = sorted(xs); k = (len(xs) - 1) * p; f = int(k); c = min(f + 1, len(xs) - 1)
    return xs[f] + (xs[c] - xs[f]) * (k - f)


def stats(xs):
    return (f"moy {st.mean(xs):.5f} · méd {q(xs, .5):.5f} · p90 {q(xs, .9):.5f} · "
            f"p95 {q(xs, .95):.5f} · max {max(xs):.5f}")


def load_device(path):
    out = {}
    for r in csv.DictReader(open(path, encoding='utf-8'), delimiter='\t'):
        out[r['id']] = dict(hyp=r['hypothesis'].replace('⏎', '\n'), text=r['polished'].replace('⏎', '\n'),
                            outcome=r['outcome'], asr=float(r['asr_ms']), pol=float(r['polish_ms']),
                            wall=float(r['polish_wall_ms']) if r.get('polish_wall_ms') else None,
                            thermal=r.get('thermal', ''))
    return out


def load_mac(v3, show):
    asr = {r['id']: r for r in csv.DictReader(open(v3, encoding='utf-8'), delimiter='\t')}
    out = {}
    for b in open(show, encoding='utf-8').read().split("━━ ")[1:]:
        m = re.match(r"\[(.+?)\]", b)
        pol = re.search(r"polished:\s?(.*?)\n\s+\((\w+), (\d+)ms", b, re.S)
        if m and pol and m.group(1) in asr:
            i = m.group(1)
            out[i] = dict(hyp=asr[i]['hypothesis'], text=pol.group(1).replace('⏎', '\n'), outcome=pol.group(2),
                          asr=float(asr[i]['latency_ms']), pol=float(pol.group(3)), thermal='')
    return out


norm = lambda s: s.lower().replace('’', "'")


def score(cases, R):
    ids = [i for i in cases if i in R]
    r = dict(n=len(ids))
    tot = [R[i]['asr'] + R[i]['pol'] for i in ids]
    r['asr'] = stats([R[i]['asr'] for i in ids])
    r['pol'] = stats([R[i]['pol'] for i in ids])
    r['tot'] = stats(tot)
    r['le1'] = 100 * sum(t <= 1000 for t in tot) / len(tot)
    r['le2'] = 100 * sum(t <= 2000 for t in tot) / len(tot)
    if all(R[i].get('wall') is not None for i in ids):
        wall = [R[i]['wall'] for i in ids]
        called = [R[i]['wall'] for i in ids if R[i]['outcome'] not in ('skippedClean', 'skipped', 'overTimeBudget')]
        e2e = [R[i]['asr'] + R[i]['wall'] for i in ids]
        r['wall'] = stats(wall); r['wall_called'] = stats(called) if called else '-'
        r['e2e'] = stats(e2e)
        r['wall_p95'] = q(wall, .95)
        r['e2e_le1'] = 100 * sum(t <= 1000 for t in e2e) / len(e2e)
        r['e2e_le2'] = 100 * sum(t <= 2000 for t in e2e) / len(e2e)
    r['skip'] = 100 * sum(R[i]['outcome'] in ('skippedClean', 'overTimeBudget') for i in ids) / len(ids)
    hot = [i for i in ids if R[i]['thermal'] in ('serious', 'critical')]
    r['hot'] = len(hot)
    # A: self-corrections, scorable only when the transcription kept both words.
    A = [i for i in ids if cases[i]['cat'] == 'A' and norm(cases[i]['wrong']) in norm(R[i]['hyp'])
         and norm(cases[i]['right']) in norm(R[i]['hyp'])]
    ok = [i for i in A if norm(cases[i]['right']) in norm(R[i]['text'])
          and not re.search(r'\b' + re.escape(norm(cases[i]['wrong'])) + r'\b', norm(R[i]['text']))]
    r['A'] = (len(ok), len(A))
    cat = lambda c: [i for i in ids if cases[i]['cat'] == c]
    r['B'] = (sum(':' in R[i]['text'] for i in cat('B')), len(cat('B')))
    r['C'] = (sum(':' in R[i]['text'] for i in cat('C')), len(cat('C')))
    r['D'] = (sum('\n' in R[i]['text'] for i in cat('D')), len(cat('D')))
    r['E'] = (sum('\n' in R[i]['text'] for i in cat('E')), len(cat('E')))
    gw = r'\b(bonjour|bonsoir|salut|coucou|cher|chère|madame|monsieur)\b'
    r['Dinv'] = sum(1 for i in ids if cases[i]['cat'] in 'DE'
                    and len(re.findall(gw, norm(R[i]['text']))) > len(re.findall(gw, norm(R[i]['hyp']))))
    hes = [i for i in ids if re.search(r'\b(euh|uh|hum)\b', norm(R[i]['hyp']))]
    r['H'] = (sum(not re.search(r'\b(euh|uh|hum)\b', norm(R[i]['text'])) for i in hes), len(hes))
    return r


def main(argv):
    cases = {c['id']: c for c in json.load(open(argv[0], encoding='utf-8'))}
    runs, args, k = [], argv[1:], 0
    while k < len(args):
        if args[k] == '--device':
            runs.append(['iphone', load_device(args[k + 1])]); k += 2
        elif args[k] == '--mac':
            runs.append(['mac', load_mac(args[k + 1], args[k + 2])]); k += 3
        elif args[k] == '--load':
            print("== chargement des modèles (ms)")
            for line in open(args[k + 1], encoding='utf-8'):
                f = line.rstrip('\n').split('\t')
                if len(f) >= 2:
                    print(f"  {f[0]}: {float(f[1]):.5f}  ({f[2] if len(f) > 2 else ''})")
            k += 2
        elif args[k] == '--label':
            runs[-1][0] = args[k + 1]; k += 2
        else:
            sys.exit(f"unknown argument {args[k]}")
    results = {}
    for label, R in runs:
        r = results[label] = score(cases, R)
        print(f"== {label} (n={r['n']})  modèle sauté {r['skip']:.5f} %  chauffe sérieuse/critique: {r['hot']} clips")
        print("  transcription ms:", r['asr'])
        print("  nettoyage ms    :", r['pol'])
        print("  total ms        :", r['tot'])
        print(f"  ≤ 1 s {r['le1']:.5f} %  ≤ 2 s {r['le2']:.5f} %")
        if 'wall' in r:
            print("  nettoyage complet ms (passes déterministes comprises), toutes dictées:", r['wall'])
            print("  nettoyage complet ms, dictées passées au modèle:", r['wall_called'])
            print("  fin de parole → texte ms:", r['e2e'])
            print(f"  fin de parole → texte ≤ 1 s {r['e2e_le1']:.5f} %  ≤ 2 s {r['e2e_le2']:.5f} %")
            ok = 'OK' if r['wall_p95'] <= 1000 else 'NON'
            print(f"  seuil nettoyage p95 ≤ 1 s: {ok} ({r['wall_p95']:.5f} ms)")
        for key, lab in [('A', 'reprises corrigées'), ('B', '« : » placés'), ('C', '« : » parasites'),
                         ('D', 'mails mis en lignes'), ('E', 'SMS/faux mails cassés'), ('H', 'hésitations retirées')]:
            a, b = r[key]; print(f"  {lab}: {a}/{b} = {100 * a / max(b, 1):.5f} %")
        print(f"  salutations inventées: {r['Dinv']}")
    return results


if __name__ == '__main__':
    main(sys.argv[1:])
