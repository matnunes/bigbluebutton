# Script to create firefox profiles in a server

# We first create a virtual Xvfb display to avoid 'Error: no display specified'
Xvfb :98 &

# Get first and last display ID's from converter.yml configuration file
FIRST_ID=$(grep display_first_id: ../converter.yml | cut -d\: -f2)
LAST_ID=$(grep display_last_id: ../converter.yml | cut -d\: -f2)

for DISPLAY_ID in $(seq $FIRST_ID $LAST_ID)
do
	# Now we create all desirable profiles ID's
	DISPLAY=:98 firefox -CreateProfile $DISPLAY_ID
done

# Killing all firefox instances
pkill firefox

# Killing virtual display
pkill Xvfb