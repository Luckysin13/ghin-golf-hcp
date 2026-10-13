/// English count + noun ("1 round", "3 rounds").
String plural(int n, String noun) => '$n $noun${n == 1 ? '' : 's'}';
