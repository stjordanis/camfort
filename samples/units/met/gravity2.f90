program gravity
  != unit m**3 / s**2 / kg :: G
  real :: G = 6.67408E-11

  != unit kg :: mE, mS
  real :: mE = 5.972E24, mS = 1.989E30

  != unit m :: rSE
  real :: rSE = 1.496E11

  != unit 1 :: pi
  real :: pi = 3.1415926

  != unit s / day :: sec_per_day
  real :: sec_per_day = 86400

  != unit m :: c
  real :: f, v, c, d

  ! gravitational force between Sun and Earth
  f = G * mE * (mS / sqr(rSE))

  ! velocity of Earth around Sun
  v = sqrt(G * mS / rSE)

  ! circumference of orbit (assuming circular)
  c = 2 * pi * rSE

  ! number of days for modelled orbital circuit
  d = c / v / sec_per_day

  print *, f, v, c, d

contains
  != unit 'a**2 :: sqr
  real function sqr(x)
    != unit 'a :: x
    real :: x
    sqr = x * x
  end function sqr
end program gravity
