module StatsHelper
  def canasta_stat(hash, key)
    hash[key.to_s].to_i
  end

  def canasta_stat_pct(num, denom)
    return 0 if denom.to_i.zero?
    ((num.to_f / denom) * 100).round
  end
end
