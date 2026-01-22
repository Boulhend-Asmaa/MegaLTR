#!/usr/bin/env python
# coding: utf-
import sys,os
figure_distrbution5_ok=sys.argv[1]
gene_anno_counter_ok=sys.argv[2]
test_karyotype_sort_head=sys.argv[3]
mappfile=sys.argv[4]
index={}
with open (f"{test_karyotype_sort_head}","r") as fp,open (mappfile,"w") as out:
    out.write(f"Chr\tmap\n")
    for ind ,line in enumerate(fp.readlines()[1:]):
        index[line.split("\t")[0]]=str(ind+1)
        index["Chr"]='Chr'
        index["chr"]='chr'
        kk=line.split('\t')[0]
        out.write(f"{kk}\t{ind+1}\n")
with open (f"{figure_distrbution5_ok}","r") as fp,open ("figure_distrbution5_ok_tmp","w") as out:
    for line in fp.readlines():
        parts = line.split("\t")
        if len(parts) >= 3 and parts[2] in index:
            ss = line.replace(parts[2], index[parts[2]])
            out.write(f'{ss}')
        else:
            # Keep header or skip malformed lines
            out.write(line)
with open (f"{gene_anno_counter_ok}","r") as fp,open ("gene_anno_counter_oko_tmp","w") as out:
    for line in fp.readlines():
        parts = line.split("\t")
        if len(parts) >= 1 and parts[0] in index:
            ss = line.replace(parts[0], index[parts[0]])
            out.write(f'{ss}')
        else:
            # Keep header or skip malformed lines
            out.write(line)  
with open (f"{test_karyotype_sort_head}","r") as fp,open ("test_karyotype_sort_head_tmp","w") as out:
    for line in fp.readlines():
        parts = line.split("\t")
        if len(parts) >= 1 and parts[0] in index:
            ss = line.replace(parts[0], index[parts[0]])
            out.write(f'{ss}')
        else:
            # Keep header or skip malformed lines
            out.write(line)
os.remove(figure_distrbution5_ok)
os.rename(f"figure_distrbution5_ok_tmp"  ,f"{figure_distrbution5_ok}")
os.remove(gene_anno_counter_ok)
os.rename(f"gene_anno_counter_oko_tmp", f"{gene_anno_counter_ok}")
os.remove(test_karyotype_sort_head)
os.rename(f"test_karyotype_sort_head_tmp" ,f"{test_karyotype_sort_head}")
