xquery version "1.0-ml";
module namespace fwc = "http://www.marklogic.com/custom/fwc";
import module namespace sem = "http://marklogic.com/semantics" at "/MarkLogic/semantics.xqy";


declare function fwc:create-graph-override-param($graphuri) 
{
  fn:concat("override-graph=", $graphuri)
};

declare function fwc:insert-inferred-Triples($triples, $graphuri)
{
  let $graphparam := fwc:create-graph-override-param($graphuri) 

  for $binding in $triples 
    return xdmp:spawn-function(function() { 
      sem:rdf-insert( 
      sem:triple(map:get ($binding, 's'), map:get ($binding, 'p'), map:get ($binding, 'o')), 
      $graphparam , (), ("Inferred") 
    )
  }, 
  <options xmlns="xdmp:eval">
    <transaction-mode>update-auto-commit</transaction-mode>
  </options>)
};

declare function fwc:slice-Sequence($seq, $amount) 
{
  let $sizeofSeq := fn:count($seq)
  let $remainder := math:fmod($sizeofSeq, $amount)
  let $slices := xs:integer($sizeofSeq div $amount)
 
  let $data := for $i in (0 to $slices)
    let $_ := xdmp:set($i, $i * $amount)
    let $slice := fn:subsequence($seq, $i+1, $amount)
  return <slice>{$slice}</slice>
  
  let $info :=  <info>
                  <slices>{$slices}</slices>
                  <remainder>{$remainder}</remainder>
                </info>
				
  let $_ := fwc:send-signalR-Message(fwc:get-default-SignalRhost(), fn:concat($slices, " slices of ", $amount, " each" ))
  
  return <res>
          {$info}
          <data>{$data}</data>
         </res>
};

declare function fwc:spawn-InsertTriples($data, $graphuri) 
{
  let $graphparam := fwc:create-graph-override-param($graphuri) 
  
  
   return xdmp:spawn-function(function() { 
      sem:rdf-insert( 
               $data, 
               $graphparam, (), ("Inferred") 
               ), xdmp:commit()
            }, 
              <options xmlns="xdmp:eval">
                <transaction-mode>update-auto-commit</transaction-mode>
              </options>)
};

declare function fwc:spawn-sliceSequence($seq, $amount, $graphuri) 
{
  xdmp:spawn-function(function() { 
      let $data := fwc:slice-Sequence($seq, $amount) 
      let $json := fn:exists($data//slice/json:object)

      for $map in $data//slice
        let $bindings := if ( $json ) then map:map($map/json:object) else map:map($map/map:map)
        let $triples := for $binding in $bindings 
          return sem:triple(map:get ($binding, 's'), map:get ($binding, 'p'), map:get ($binding, 'o'))
      return fwc:spawn-InsertTriples($triples, $graphuri)
    }, 
    <options xmlns="xdmp:eval">
      <transaction-mode>update-auto-commit</transaction-mode>
    </options>)


};

declare function fwc:genTriples($itemcount)
{
  for $i in (1 to $itemcount)

  return map:new((
    map:entry("s", fn:concat("http://temp.org/", fn:format-number($i, "000"))),
    map:entry("p", fn:concat("http://temp.org/predicate/", fn:format-number($i, "000"))),
    map:entry("o", fn:concat("_item", fn:format-number($i, "000")))
  ))
};

declare function fwc:get-defaultSparql($graphuri)
{
	let $front := "PREFIX rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
				PREFIX a1: <http://www.co-ode.org/roberts/family-tree.owl#>
				select ?s ?p ?o "
	let $trail := "WHERE
				   { ?s ?p ?o }"
    return fn:concat($front, "FROM <", $graphuri, "> ", $trail)
};

declare function fwc:get-inferred-Triples($rules, $sparql, $rdfs-store)
{
	let $_ := fwc:send-signalR-Message(fwc:get-default-SignalRhost(), "start inferring triples")
	let $triples := sem:sparql($sparql,(), (), $rdfs-store)
	let $_ := fwc:send-signalR-Message(fwc:get-default-SignalRhost(), fn:concat("finished inferring ", fn:count($triples), " triples"))
	
	return $triples
};

declare function fwc:infer-Triples($rules, $sparql, $rdfs-store, $target-graphuri, $slice-size)
{
	let $triples := fwc:get-inferred-Triples($rules, $sparql, $rdfs-store)
	return fwc:spawn-sliceSequence($triples, $slice-size, $target-graphuri) 
};

declare function fwc:spawn-infer-Triples($rules, $sparql, $rdfs-store, $target-graphuri, $slice-size)
{
	xdmp:spawn-function(function() { 
	 fwc:send-signalR-Message(fwc:get-default-SignalRhost(), "spawning ingestion Tasks"),
	 fwc:infer-Triples($rules, $sparql, $rdfs-store, $target-graphuri, $slice-size),
	 fwc:send-signalR-Message(fwc:get-default-SignalRhost(), "finsihed spawning ingestion Tasks")
	 }, 
    <options xmlns="xdmp:eval">
      <transaction-mode>update-auto-commit</transaction-mode>
    </options>)
	
	
};

declare function fwc:send-signalR-Message($url, $message)
{
	xdmp:spawn-function(function () {
		let $object := json:object()
		let $_ := (
		  map:put($object, "Time", fn:current-dateTime()),
		  map:put($object, "User", xdmp:get-current-user() ),
		  map:put($object, "Message", $message )
		  )

		let $json := xdmp:to-json($object)
		let $payload := xdmp:quote($json)

		return xdmp:http-post($url,

		<options xmlns="xdmp:http">
			   <data>{$payload}</data>
			   <headers>
				 <content-type>application/json</content-type>
			   </headers>
			 </options>
			 )
	})
};

declare function fwc:get-default-SignalRhost()
{
	let $url := "http://mario-win8:5000/api/trigger"
	return $url
};