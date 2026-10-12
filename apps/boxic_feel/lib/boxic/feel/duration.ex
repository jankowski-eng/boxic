defmodule Boxic.FEEL.Duration do
  @moduledoc """
  FEEL duration value.

  FEEL defines year-month and day-time durations as distinct, generally
  incomparable kinds. A single elapsed-seconds value cannot represent calendar
  months, while Elixir's date/time APIs do not provide a value that preserves
  this FEEL distinction or fractional duration seconds.

  The explicit `kind` field prevents accidental comparison or property access
  across the two domains. Year-month values use `months`; day-time values use
  `seconds`, with `Decimal` retained when fractional precision is present.
  """

  defstruct [:kind, :months, :seconds]

  @max_magnitude Decimal.new("1E+34")

  @type kind :: :year_month | :day_time
  @type t :: %__MODULE__{kind: kind(), months: integer(), seconds: integer() | Decimal.t()}

  @doc """
  Parses an ISO 8601 year-month or day-time duration.

      Boxic.FEEL.Duration.parse_iso8601("P1Y2M")
  """
  @spec parse_iso8601(String.t()) :: {:ok, t()} | {:error, :invalid_duration}
  def parse_iso8601(value) when is_binary(value) do
    regex =
      ~r/^(?<sign>-)?P(?:(?<years>\d+)Y)?(?:(?<months>\d+)M)?(?:(?<days>\d+)D)?(?:T(?:(?<hours>\d+)H)?(?:(?<minutes>\d+)M)?(?:(?<seconds>\d+(?:\.\d*)?)S)?)?$/

    case Regex.named_captures(regex, value) do
      nil ->
        {:error, :invalid_duration}

      captures ->
        if Enum.all?(~w(years months days hours minutes seconds), &(captures[&1] in [nil, ""])) do
          {:error, :invalid_duration}
        else
          years = int(captures["years"])
          months = int(captures["months"])
          days = int(captures["days"])
          hours = int(captures["hours"])
          minutes = int(captures["minutes"])
          seconds = number(captures["seconds"])

          sign = if captures["sign"] == "-", do: -1, else: 1

          kind =
            if captures["years"] not in [nil, ""] or captures["months"] not in [nil, ""],
              do: :year_month,
              else: :day_time

          {:ok,
           %__MODULE__{
             kind: kind,
             months: sign * (years * 12 + months),
             seconds:
               multiply(sign, add_number(days * 86_400 + hours * 3_600 + minutes * 60, seconds))
           }}
        end
    end
  end

  @doc """
  Creates a day-time duration from whole days.

      Boxic.FEEL.Duration.from_days(2)
  """
  @spec from_days(integer()) :: t()
  def from_days(days), do: %__MODULE__{kind: :day_time, months: 0, seconds: days * 86_400}

  @doc """
  Creates a day-time duration from seconds.

      Boxic.FEEL.Duration.from_seconds(90)
  """
  @spec from_seconds(integer() | Decimal.t()) :: t()
  def from_seconds(seconds), do: %__MODULE__{kind: :day_time, months: 0, seconds: seconds}

  @doc """
  Negates a duration.

      Boxic.FEEL.Duration.negate(duration)
  """
  @spec negate(t()) :: t()
  def negate(%__MODULE__{kind: kind, months: months, seconds: seconds}) do
    %__MODULE__{kind: kind, months: -months, seconds: multiply(-1, seconds)}
  end

  @doc """
  Returns the absolute duration.

      Boxic.FEEL.Duration.abs(duration)
  """
  @spec abs(t()) :: t()
  def abs(%__MODULE__{kind: kind, months: months, seconds: seconds}) do
    %__MODULE__{kind: kind, months: Kernel.abs(months), seconds: abs_number(seconds)}
  end

  @doc """
  Adds durations of the same kind.

      Boxic.FEEL.Duration.add(left, right)
  """
  @spec add(t(), t()) :: t()
  def add(%__MODULE__{kind: kind} = left, %__MODULE__{kind: kind} = right) do
    %__MODULE__{
      kind: kind,
      months: left.months + right.months,
      seconds: add_number(left.seconds, right.seconds)
    }
  end

  @doc """
  Subtracts `right` from `left`.

      Boxic.FEEL.Duration.subtract(left, right)
  """
  @spec subtract(t(), t()) :: t()
  def subtract(%__MODULE__{} = left, %__MODULE__{} = right), do: add(left, negate(right))

  @doc """
  Multiplies a duration by a decimal factor.

      Boxic.FEEL.Duration.scale(duration, Decimal.new("1.5"))

  Year-month results are truncated to whole months. Returns `:error` when the factor is not
  a finite number or the result is not representable, that is, when it has more than 34
  digits before the decimal point.
  """
  @spec scale(t(), Decimal.t()) :: {:ok, t()} | :error
  def scale(%__MODULE__{} = duration, %Decimal{coef: coef} = factor) when is_integer(coef) do
    product = Decimal.mult(scalable(duration), factor)

    if representable?(product) do
      {:ok, scaled(duration, product)}
    else
      :error
    end
  end

  def scale(%__MODULE__{}, _factor), do: :error

  defp scalable(%__MODULE__{kind: :year_month, months: months}), do: Decimal.new(months)
  defp scalable(%__MODULE__{seconds: seconds}), do: decimal(seconds)

  defp scaled(%__MODULE__{kind: :year_month} = duration, product) do
    {months, _fraction} = split_seconds(product)
    %{duration | months: months, seconds: 0}
  end

  defp scaled(%__MODULE__{} = duration, %Decimal{coef: 0}),
    do: %{duration | months: 0, seconds: Decimal.new(0)}

  defp scaled(%__MODULE__{} = duration, product), do: %{duration | months: 0, seconds: product}

  # Decimal turns an overflow into an infinity, and a number with more than 34 integer
  # digits cannot be processed further.
  defp representable?(%Decimal{coef: coef} = value) when is_integer(coef),
    do: Decimal.compare(Decimal.abs(value), @max_magnitude) == :lt

  defp representable?(_value), do: false

  @doc """
  Divides two durations of the same kind.

      Boxic.FEEL.Duration.ratio(left, right)
  """
  @spec ratio(t(), t()) :: {:ok, Decimal.t()} | :error
  def ratio(%__MODULE__{kind: kind} = left, %__MODULE__{kind: kind} = right) do
    {left_value, right_value} =
      if kind == :year_month,
        do: {Decimal.new(left.months), Decimal.new(right.months)},
        else: {decimal(left.seconds), decimal(right.seconds)}

    if Decimal.equal?(right_value, Decimal.new(0)),
      do: :error,
      else: {:ok, Decimal.div(left_value, right_value)}
  end

  def ratio(%__MODULE__{}, %__MODULE__{}), do: :error

  @doc """
  Compares durations of the same kind.

      Boxic.FEEL.Duration.compare(left, right)
  """
  @spec compare(t(), t()) :: :lt | :eq | :gt | :unordered
  def compare(%__MODULE__{kind: kind} = left, %__MODULE__{kind: kind} = right) do
    case kind do
      :year_month -> compare_numbers(left.months, right.months)
      :day_time -> compare_numbers(left.seconds, right.seconds)
    end
  end

  def compare(%__MODULE__{}, %__MODULE__{}), do: :unordered

  @doc """
  Serializes a duration as ISO 8601 text.

      Boxic.FEEL.Duration.to_string(duration)
  """
  @spec to_string(t()) :: String.t()
  def to_string(%__MODULE__{kind: :year_month, months: months}) do
    sign = if months < 0, do: "-", else: ""
    months = Kernel.abs(months)
    years = div(months, 12)
    remainder = rem(months, 12)

    body =
      cond do
        years > 0 and remainder > 0 -> "#{years}Y#{remainder}M"
        years > 0 -> "#{years}Y"
        true -> "#{remainder}M"
      end

    sign <> "P" <> body
  end

  def to_string(%__MODULE__{kind: :day_time, seconds: seconds}) do
    seconds = decimal(seconds)
    sign = if Decimal.negative?(seconds), do: "-", else: ""
    {whole, fraction} = seconds |> Decimal.abs() |> split_seconds()
    days = div(whole, 86_400)
    hours = div(rem(whole, 86_400), 3_600)
    minutes = div(rem(whole, 3_600), 60)
    second = Decimal.add(Decimal.new(rem(whole, 60)), fraction)
    date_part = if days > 0, do: "#{days}D", else: ""

    time_part =
      [
        if(hours > 0, do: "#{hours}H"),
        if(minutes > 0, do: "#{minutes}M"),
        if(Decimal.equal?(second, Decimal.new(0)) and (days > 0 or hours > 0 or minutes > 0),
          do: nil,
          else: format_seconds(second)
        )
      ]
      |> Enum.reject(&is_nil/1)
      |> Enum.join()

    time_marker = if time_part == "", do: "", else: "T"
    sign <> "P" <> date_part <> time_marker <> time_part
  end

  @doc """
  Adds a duration to an Elixir date.

      Boxic.FEEL.Duration.add_to_date(~D[2026-01-01], duration)
  """
  @spec add_to_date(Date.t(), t()) :: Date.t()
  def add_to_date(%Date{} = date, %__MODULE__{} = duration) do
    date
    |> add_months(duration.months)
    |> Date.add(floor_days(duration.seconds))
  end

  @doc """
  Adds a duration to an Elixir date-time, in the date-time's own time zone.

      Boxic.FEEL.Duration.add_to_datetime(datetime, duration)

  Returns `:error` when the shifted wall-clock time does not exist in the zone, or when the
  zone is not in the `tz` time zone database. A wall-clock time that occurs twice resolves to
  the earlier occurrence.
  """
  @spec add_to_datetime(DateTime.t(), t()) :: {:ok, DateTime.t()} | :error
  def add_to_datetime(%DateTime{} = datetime, %__MODULE__{} = duration) do
    shifted_date = add_months(DateTime.to_date(datetime), duration.months)
    {seconds, _fraction} = split_seconds(duration.seconds)

    case DateTime.new(
           shifted_date,
           DateTime.to_time(datetime),
           datetime.time_zone,
           Tz.TimeZoneDatabase
         ) do
      {:ok, shifted} ->
        {:ok, DateTime.add(shifted, seconds, :second, Tz.TimeZoneDatabase)}

      {:ambiguous, first, _second} ->
        {:ok, DateTime.add(first, seconds, :second, Tz.TimeZoneDatabase)}

      _gap_or_error ->
        :error
    end
  end

  @doc """
  Adds a day-time duration to an Elixir time.

      Boxic.FEEL.Duration.add_to_time(~T[12:00:00], duration)
  """
  @spec add_to_time(Time.t(), t()) :: Time.t()
  def add_to_time(%Time{} = time, %__MODULE__{} = duration) do
    total_seconds =
      rem(
        time.hour * 3_600 + time.minute * 60 + time.second + truncate(duration.seconds),
        86_400
      )

    normalized = if total_seconds < 0, do: total_seconds + 86_400, else: total_seconds

    hour = div(normalized, 3_600)
    minute = div(rem(normalized, 3_600), 60)
    second = rem(normalized, 60)

    {:ok, result} = Time.new(hour, minute, second)
    result
  end

  @doc false
  # Splits seconds into the whole seconds, truncated toward zero, and the fraction that is
  # left, which has the same sign. This is integer arithmetic on the digits of the number,
  # unlike Decimal.round/3 and Decimal.div_int/2, which fail for numbers with more digits
  # than the Decimal context allows.
  @spec split_seconds(integer() | Decimal.t()) :: {integer(), Decimal.t()}
  def split_seconds(seconds) when is_integer(seconds), do: {seconds, Decimal.new(0)}

  def split_seconds(%Decimal{sign: sign, coef: coef, exp: exp}) when is_integer(coef) do
    if exp >= 0 do
      {sign * coef * Integer.pow(10, exp), Decimal.new(0)}
    else
      divisor = Integer.pow(10, -exp)
      {sign * div(coef, divisor), %Decimal{sign: sign, coef: rem(coef, divisor), exp: exp}}
    end
  end

  @doc false
  # The number of whole days that `seconds` reaches, rounded toward negative infinity.
  @spec floor_days(integer() | Decimal.t()) :: integer()
  def floor_days(seconds) do
    {whole, fraction} = split_seconds(seconds)
    floor_seconds = if fraction.sign == -1 and fraction.coef != 0, do: whole - 1, else: whole
    Integer.floor_div(floor_seconds, 86_400)
  end

  defp add_months(%Date{} = date, 0), do: date

  defp add_months(%Date{} = date, months_delta) do
    total_month = date.month + months_delta
    year = date.year + floor_div(total_month - 1, 12)
    month = Integer.mod(total_month - 1, 12) + 1
    day = min(date.day, Date.days_in_month(%Date{year: year, month: month, day: 1}))

    {:ok, shifted} = Date.new(year, month, day)
    shifted
  end

  defp floor_div(value, divisor) do
    quotient = div(value, divisor)
    remainder = rem(value, divisor)

    if remainder < 0 do
      quotient - 1
    else
      quotient
    end
  end

  defp int(nil), do: 0
  defp int(""), do: 0
  defp int(value), do: String.to_integer(value)

  defp number(nil), do: 0
  defp number(""), do: 0

  defp number(value) do
    if String.contains?(value, "."),
      do: Decimal.new(String.trim_trailing(value, ".")),
      else: int(value)
  end

  defp decimal(%Decimal{} = value), do: value
  defp decimal(value), do: Decimal.new(value)

  defp format_seconds(value) do
    if Decimal.equal?(value, Decimal.new(0)) do
      "0S"
    else
      Decimal.to_string(value, :normal) <> "S"
    end
  end

  defp add_number(%Decimal{} = left, right), do: Decimal.add(left, Decimal.new(right))
  defp add_number(left, %Decimal{} = right), do: Decimal.add(Decimal.new(left), right)
  defp add_number(left, right), do: left + right

  defp multiply(multiplier, %Decimal{} = value), do: Decimal.mult(Decimal.new(multiplier), value)
  defp multiply(multiplier, value), do: multiplier * value

  defp abs_number(%Decimal{} = value), do: Decimal.abs(value)
  defp abs_number(value), do: Kernel.abs(value)

  defp truncate(seconds), do: seconds |> split_seconds() |> elem(0)

  defp compare_numbers(%Decimal{} = left, %Decimal{} = right), do: Decimal.compare(left, right)
  defp compare_numbers(%Decimal{} = left, right), do: Decimal.compare(left, Decimal.new(right))
  defp compare_numbers(left, %Decimal{} = right), do: Decimal.compare(Decimal.new(left), right)
  defp compare_numbers(left, right) when left < right, do: :lt
  defp compare_numbers(left, right) when left > right, do: :gt
  defp compare_numbers(_left, _right), do: :eq
end
