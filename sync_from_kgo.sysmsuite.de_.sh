echo Starting to sync...
rsync --recursive --update --links --times --delete kgo.symsuite.de:/usr/home/kgosymsu/public_html/.webchunks/$(basename $(pwd))/ . 
echo ... done.
du -h
